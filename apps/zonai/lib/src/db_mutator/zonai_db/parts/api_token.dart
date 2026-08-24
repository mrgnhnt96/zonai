part of zonai_db;

/// A freshly minted token: the row that will be stored, and the plaintext
/// that will not be.
///
/// [secret] is returned exactly once, from exactly here. Nothing can recover
/// it afterwards -- the row keeps only its SHA-256 -- so a caller that does
/// not show it to someone has lost it.
typedef MintedApiToken = ({String secret, ApiTokenEntry row});

extension _ApiTokenX on ZonaiDb {
  Future<MintedApiToken> _createApiToken({
    required String name,
    required ApiTokenScope scope,
    required String createdBy,
    Map<String, dynamic> claims = const {},
    String? boundTable,
    String? boundUserId,
    DateTime? expiresAt,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const InvalidApiTokenScopeException(
        'a token needs a name -- an unnamed credential is one nobody ever '
        'revokes, because nobody can tell what would break',
      );
    }

    _validateApiTokenScope(scope);

    if ((boundTable == null) != (boundUserId == null)) {
      throw const InvalidApiTokenScopeException(
        'bind a token to both a table and a row id, or to neither',
      );
    }

    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    if (boundTable != null && boundUserId != null) {
      // Checked now, while there is someone to tell. A binding that names no
      // row produces a token that authenticates and then matches nothing,
      // which reads as "the rules are wrong" from every angle except this one.
      final row = await _boundUserRowFor(
        table: boundTable,
        userId: boundUserId,
      );
      if (row.isEmpty) {
        throw InvalidApiTokenScopeException(
          'no row "$boundUserId" in "$boundTable" to bind to',
        );
      }
    }

    final secret = ApiTokenSecret.generate();
    final row = ApiTokenEntry.create(
      name: trimmedName,
      tokenHash: ApiTokenSecret.hash(secret),
      tokenPrefix: ApiTokenSecret.displayPrefix(secret),
      scope: scope,
      createdBy: createdBy,
      claims: claims,
      boundTable: boundTable,
      boundUserId: boundUserId,
      expiresAt: expiresAt,
    );

    await db.insert(into: apiTokens).values([row]);

    logger.info(
      'Created API token "${row.name}" (${row.id.value}), '
      '${row.expiresAt == null ? 'no expiry' : 'expires ${row.expiresAt}'}',
    );

    return (secret: secret, row: row);
  }

  /// Every token on the deployment, newest first, never the hash.
  Future<List<ApiTokenEntry>> _listApiTokens({
    bool includeRevoked = false,
  }) async {
    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    final rows = await db.select().from(apiTokens);
    final visible = [
      for (final row in rows)
        if (includeRevoked || !row.isRevoked) row,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return visible;
  }

  /// Stamps `revoked_at`. The token stops working on the very next request:
  /// resolution reads this row every time, so there is no cache to wait out,
  /// no restart, and no redeploy.
  ///
  /// A stamp rather than a delete, so "who had access, and until when" is
  /// still answerable afterwards. `zonai db token revoke --forget` and the
  /// dashboard's delete are the blunt versions for when the row itself is
  /// the thing to be rid of.
  Future<ApiTokenEntry> _revokeApiToken({required String id}) async {
    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    final row = await _apiTokenById(id);

    if (row.isRevoked) {
      // Idempotent on purpose: "revoke this" asked twice is not an error, and
      // the second answer should not read like the token is still live.
      return row;
    }

    await db
        .update(apiTokens)
        .set(apiTokens.revokedAt.to(clock.now()))
        .where(apiTokens.id.equals(row.id));

    logger.info('Revoked API token "${row.name}" (${row.id.value})');

    return await _apiTokenById(id);
  }

  /// Deletes the row outright. Loses the audit trail [_revokeApiToken] keeps.
  Future<void> _deleteApiToken({required String id}) async {
    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    final row = await _apiTokenById(id);
    await db.delete(from: apiTokens).where(apiTokens.id.equals(row.id));

    logger.info('Deleted API token "${row.name}" (${row.id.value})');
  }

  /// Resolves [id] as a full token id or as a unique prefix of one.
  ///
  /// Prefix matching because the id is what a human retypes off a list, and
  /// the full one is 19 characters of hash. Ambiguity is refused rather than
  /// guessed -- picking the "first match" for a revoke is how the wrong
  /// integration goes down.
  Future<ApiTokenEntry> _apiTokenById(String id) async {
    final needle = id.trim();
    if (needle.isEmpty) {
      throw const ApiTokenNotFoundException(id: '');
    }

    final rows = await _listApiTokens(includeRevoked: true);
    final matches = [
      for (final row in rows)
        if (row.id.value == needle) row,
    ];
    if (matches.length == 1) return matches.single;

    final prefixed = [
      for (final row in rows)
        if (row.id.value.startsWith(needle)) row,
    ];
    return switch (prefixed) {
      [final only] => only,
      [] => throw ApiTokenNotFoundException(id: needle),
      _ => throw InvalidApiTokenScopeException(
        '"$needle" matches ${prefixed.length} tokens -- use the full id',
      ),
    };
  }

  /// The bound row, sanitized, or empty when there is none.
  Future<Map<String, Object?>> _boundUserRowFor({
    required String table,
    required String userId,
  }) async {
    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );
    final idColumnName = idColumn.name;
    if (idColumnName == null) return const {};

    final operation = await _getOperation(
      ReadOperationRequest(
        table: table,
        where: Eq(idColumnName, userId),
        jwt: null,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) return const {};

    final object = result.rows.singleOrNull?.toMap();
    if (object == null) return const {};

    return await _sanitizeRow(table, object);
  }

  /// Refuses a scope that could not have been meant, before a row exists to
  /// carry it.
  void _validateApiTokenScope(ApiTokenScope scope) {
    if (scope.tables.isEmpty) {
      throw const InvalidApiTokenScopeException(
        'name at least one table, or "*" for every app collection',
      );
    }

    if (scope.operations.isEmpty && scope.customOperations.isEmpty) {
      throw const InvalidApiTokenScopeException(
        'name at least one operation -- a token that may reach a table but '
        'perform nothing on it can do nothing at all',
      );
    }

    // The wildcard is over the app's collections. An internal table named
    // explicitly is refused here, and the gate excludes all of them from `*`
    // regardless -- `_api_tokens` most of all, because a token that can read
    // it sees every other credential's row and a token that can write it
    // mints itself a wider one.
    final internal = [
      for (final table in scope.tables)
        if (InternalDbArtifacts.tableNames.contains(table)) table,
    ]..sort();
    if (internal.isNotEmpty) {
      throw InvalidApiTokenScopeException(
        'an API token can never reach zonai\'s internal tables '
        '(${internal.join(', ')})',
      );
    }

    if (scope.canEdit && !scope.admin) {
      // Mirrors `AsAdmin.canEdit`, which is only reachable on a table that is
      // already admin. Allowing the pair apart would also be a live grant:
      // `BaseTableRules.canCreate` checks `canEdit` alone.
      throw const InvalidApiTokenScopeException(
        'canEdit is the write half of admin -- grant admin as well, or '
        'neither',
      );
    }
  }
}
