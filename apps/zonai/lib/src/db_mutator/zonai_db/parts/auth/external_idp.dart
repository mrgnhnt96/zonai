part of zonai_db;

extension _ExternalIdpX on ZonaiDb {
  /// Attempts to verify [rawJwt] against any configured external IdP.
  ///
  /// Returns the constructed [Jwt] when the token's `iss` matches a
  /// configured [ExternalIdpConfig] and verification succeeds. Returns
  /// `null` when no external IdPs are configured or when no `iss`
  /// matches — caller should treat that as "not an external token,
  /// fall through to normal handling."
  ///
  /// Throws [InvalidJwtException] when an IdP matches by `iss` but
  /// signature, algorithm, audience, expiry, or claim shape are wrong.
  /// Throws [UserNotFoundAuthException] when verification succeeds but
  /// the `sub` claim does not match a row in the configured
  /// [ExternalIdpConfig.authTable] — auto-provisioning is the
  /// follow-up issue, not this one.
  ///
  /// Skips the `_jwt` revocation table lookup that
  /// [ZonaiDb._validateJwt] performs for internally-minted tokens.
  /// External tokens are validated by the issuing IdP; recording them
  /// in zonai's revocation table is intentionally out of scope (see
  /// the design discussion on #2).
  Future<Jwt?> _tryExternalIdpJwt(String rawJwt) async {
    final config = await configResolver.resolve();
    if (config.externalIdps.isEmpty) return null;

    final issuer = _peekIssuer(rawJwt);
    if (issuer == null) return null;

    final idpConfig = config.externalIdps
        .where((idp) => idp.issuer == issuer)
        .firstOrNull;
    if (idpConfig == null) return null;

    final claims = switch (idpConfig) {
      SharedSecretIdpConfig() => SharedSecretIdpVerifier(
        idpConfig,
      ).verify(rawJwt),
      JwksIdpConfig() => throw UnimplementedError(
        'JwksIdpConfig verification is a follow-up to #2.',
      ),
    };

    return await _externalJwtFromClaims(idpConfig, claims);
  }

  /// Decodes the JWT payload segment WITHOUT verifying the signature
  /// to read its `iss` claim. The result is only used to pick an IdP
  /// config — the actual verification happens after, with the matched
  /// config's secret/keys. Returns `null` on malformed input.
  String? _peekIssuer(String rawJwt) {
    final parts = rawJwt.split('.');
    if (parts.length != 3) return null;
    try {
      final segment = parts[1];
      final padNeeded = (4 - segment.length % 4) % 4;
      final padded = padNeeded == 0 ? segment : segment + ('=' * padNeeded);
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, Object?>;
      final iss = decoded['iss'];
      return iss is String ? iss : null;
    } on Object {
      return null;
    }
  }

  /// Looks up the user row in [table] keyed by the `id` column,
  /// using the same `ReadOperationRequest` primitive that
  /// `_resetPassword` uses to fetch by id.
  Future<Map<String, Object?>?> _externalAuthUserById({
    required String table,
    required String id,
  }) async {
    final idColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );
    final idColumnName = idColumn.name;
    if (idColumnName == null) {
      throw StateError('No id column on table "$table"');
    }

    final response = await _operations.send<PerformOperationResponse>(
      ReadOperationRequest(
        table: table,
        where: Eq(idColumnName, id),
        jwt: null,
      ),
    );

    final (error, result) = await _execute((response.query, response.values));
    if (error != null) {
      throw AuthFailedException(cause: error);
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) return null;
    return await _sanitizeRow(table, user);
  }

  /// Constructs a zonai [Jwt] from verified external IdP claims by
  /// resolving the user row in the IdP's mapped auth table.
  Future<Jwt> _externalJwtFromClaims(
    ExternalIdpConfig config,
    Map<String, Object?> claims,
  ) async {
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) {
      throw const InvalidJwtException();
    }

    final user = await _externalAuthUserById(table: config.authTable, id: sub);
    if (user == null) {
      throw UserNotFoundAuthException(table: config.authTable);
    }

    final exp = claims['exp'];
    if (exp is! num) {
      // SharedSecretIdpVerifier already enforces exp; defensive cast for
      // future variants that might delegate to a different verifier path.
      throw const InvalidJwtException();
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );

    final jti = claims['jti'];
    final jwtId = JwtId(
      jti is String && jti.isNotEmpty ? jti : 'ext:${config.issuer}:$sub',
    );

    return Jwt(
      userId: UnknownId(sub),
      table: config.authTable,
      jwtId: jwtId,
      expiresAt: expiresAt,
      user: user,
      claims: claims,
      admin: (isAdmin: false, canEdit: null),
    );
  }
}
