part of zonai_db;

/// 256 bits of CSPRNG output, hex-encoded — the value a challenge secret takes
/// unless [_insecureTestMode] says otherwise.
String _randomChallengeSecret() => List.generate(
  32,
  (_) => Random.secure().nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// Whether to issue the fixed, publicly-known challenge values.
///
/// Every call logs, at error level, on the way through. A backdoor that is
/// open and silent is the shape this had before; if it is ever open on
/// something that matters, the logs should be unmissable.
bool _insecureTestMode() {
  if (!kInsecureTestMode) return false;

  logger.error(
    'INSECURE TEST MODE: issuing a fixed, publicly-known auth challenge. '
    'Anyone who knows an email address can take over that account. '
    'Unset $kInsecureTestModeVariable.',
  );
  return true;
}

extension _AuthUtilsX on ZonaiDb {
  Future<Map<String, Object?>?> _passwordRecord({
    required String table,
    required PasswordAuthPayload payload,
    required String rawPassword,
  }) async {
    final jwt = await _extractJwt(payload);

    final response = await _dispatchOperation<PerformOperationResponse>(
      ViewAuthOperationRequest(
        table: table,
        jwt: jwt,
        payload: PasswordAuthOperationPayload.get(email: payload.email),
      ),
    );

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw AuthFailedException(cause: error);
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) {
      return null;
    }

    final passwordColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .password),
    );

    final passwordHash = user.remove(passwordColumn.name);
    if (passwordHash is! String) {
      logger.trace('Password hash not found', prefix: _prefix);
      return null;
    }

    final passwordsMatch = await _hashPassword.verify(
      rawPassword: payload.password,
      passwordHash: passwordHash,
    );

    if (!passwordsMatch) {
      throw const InvalidPasswordOrEmailException();
    }

    return await _sanitizeRow(table, user);
  }

  Future<Map<String, Object?>?> _authRecord({
    required String table,
    required String email,
    bool sanitize = true,
  }) async {
    final response = await _dispatchOperation<PerformOperationResponse>(
      ViewAuthOperationRequest(
        table: table,
        jwt: null,
        payload: OtpAuthOperationPayload.get(email: email),
      ),
    );

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw AuthFailedException(cause: error);
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) {
      return null;
    }

    if (!sanitize) {
      return user;
    }

    return await _sanitizeRow(table, user);
  }

  Future<bool> _hasAuthRecord({
    required String table,
    required AuthPayload payload,
  }) async {
    final jwt = await _extractJwt(payload);

    final response = await _dispatchOperation<PerformOperationResponse>(
      ViewAuthOperationRequest(
        table: table,
        jwt: jwt,
        payload: switch (payload) {
          PasswordAuthPayload(:final email) ||
          ResetPasswordAuthPayload(
            :final email,
          ) => PasswordAuthOperationPayload.get(email: email),
          SendOtpAuthPayload(:final email) ||
          VerifyOtpAuthPayload(
            :final email,
          ) => OtpAuthOperationPayload.get(email: email),
          SendMagicLinkAuthPayload(:final email) ||
          VerifyMagicLinkAuthPayload(
            :final email,
          ) => MagicLinkAuthOperationPayload.get(email: email),
          ConfirmResetPasswordAuthPayload() => throw ArgumentError(
            'Cannot get auth record for confirm reset password payload',
          ),
          VerifyEmailAuthPayload() => throw ArgumentError(
            'Cannot get auth record for verify email payload',
          ),
          StartOAuthAuthPayload() ||
          CompleteOAuthAuthPayload() ||
          NativeOAuthAuthPayload() => throw ArgumentError(
            'Cannot get auth record for OAuth payloads — resolve identity '
            'via _oauth_identities / _authRecord instead',
          ),
        },
      ),
    );

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw AuthFailedException(cause: error);
    }

    final user = result?.rows.singleOrNull?.toMap();
    return user != null;
  }

  Future<void> _requireAuthRecordAccess(
    String table,
    AuthOperation operation,
    AuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);

    final response = await _dispatchRules<AuthRowRulesResponse>(
      AuthRowRulesRequest(
        table: table,
        jwt: jwt,
        operation: operation,
        authType: payload.authType,
      ),
    );

    if (response case AuthRowRulesResponse(canAccess: true)) {
      return;
    }

    throw TableAccessDeniedException(table: table, operation: operation.name);
  }

  /// Verifies the JWT signature and decodes claims without checking the
  /// revocation record in the database. Use only for read-only UI display
  /// (e.g. determining which buttons to show); always use [_extractJwt] for
  /// actual data access.
  Future<Jwt?> _extractJwtClaimsOnly(String? jwt) async {
    if (jwt == null) return null;

    // An API token has no "claims only" form. Its claims, its scope and its
    // validity all live in the same row, so there is no cheaper answer to
    // give here -- the same resolution runs, and the same one read decides.
    if (ApiTokenSecret.looksLike(jwt)) {
      return await _resolveApiToken(jwt);
    }

    final decoded = await _jwt.verify(jwt);
    if (decoded == null) {
      // Internal HS256 didn't match — try configured external IdPs.
      // External-trust JWTs have no `_jwt` revocation row to check, so
      // there's no separation between "claims-only" and "full" extraction
      // for them; the verified, user-resolved Jwt is returned directly.
      final externalJwt = await _tryExternalIdpJwt(jwt);
      if (externalJwt != null) return externalJwt;
      throw const InvalidJwtException();
    }

    if (Jwt.isCronWorkerPayload(decoded)) throw const InvalidJwtException();
    if (Jwt.isProvisioningWorkerPayload(decoded)) {
      throw const InvalidJwtException();
    }
    // Refused here as flatly as in [_extractJwt], and this is the path where
    // it matters most: this one deliberately skips the `_jwt` lookup, so a
    // forged token has no database read to fail on. The dashboard's SSR feeds
    // the result to `collectionActions`, so without this an attacker holding
    // the signing key is rendered the admin UI.
    if (Jwt.isApiTokenPayload(decoded)) {
      _logForgedApiTokenPayload();
      throw const InvalidJwtException();
    }

    final Jwt claimsOnly;
    try {
      claimsOnly = Jwt.fromJson(decoded);
    } on Object {
      throw const InvalidJwtException();
    }

    // Admin is re-derived here too, even though this path deliberately skips
    // the `_jwt` revocation lookup. The dashboard's SSR passes the result of
    // this to `collectionActions` to decide which controls to render, so a
    // token with a forged `admin` claim would have been shown the admin UI —
    // every button on it refused by `_extractJwt`, but shown. Deriving costs
    // one memoised schema lookup and no database access, so the "claims only"
    // property this method exists for is preserved.
    return await _withServerDerivedAdmin(claimsOnly);
  }

  Future<Jwt?> _extractJwt(
    JwtPayload payload, {
    bool allowApiToken = false,
  }) async {
    final jwt = payload.jwt;

    if (jwt == null) {
      return null;
    }

    // Tested on the shape, before anything parses the value. An API token is
    // an opaque `zonai_pat_...` string, so it must never reach the JWT
    // verifier -- and a JWT must never be looked up as a token. The prefix is
    // what makes those two doors unambiguous rather than a guess.
    //
    // [allowApiToken] defaults to false, and the default is the security
    // property: only the data paths opt in, so `/auth`, `/admin`,
    // `/maintenance`, `/cron`, `/email`, `/push` and photos all refuse one --
    // as does any path added later whose author never thought about API
    // tokens at all.
    if (ApiTokenSecret.looksLike(jwt)) {
      if (!allowApiToken) {
        throw const ApiTokenNotAcceptedHereException();
      }
      return await _resolveApiToken(jwt);
    }

    final decoded = await _jwt.verify(jwt);
    if (decoded == null) {
      // Internal HS256 didn't match — try configured external IdPs
      // before rejecting. External tokens skip [_validateJwt]
      // (revocation lives with the IdP, not in zonai's `_jwt` table).
      final externalJwt = await _tryExternalIdpJwt(jwt);
      if (externalJwt != null) return externalJwt;
      throw const InvalidJwtException();
    }

    /// Do not allow cron JWT to be a user JWT.
    if (Jwt.isCronWorkerPayload(decoded)) {
      logger.error(
        'Attempt to use cron JWT as a user JWT, this is absolutely not expected and should be considered a security threat'
        'Rotate the JWT secret and deploy a new version of the application immediately',
      );
      throw const InvalidJwtException();
    }

    /// Do not allow provisioning JWT to be a user JWT — same threat
    /// posture as the cron sentinel above. A signed bearer token
    /// with a `'PROVISIONING'` flag would bypass auth-table write
    /// restrictions if accepted as a user identity.
    if (Jwt.isProvisioningWorkerPayload(decoded)) {
      logger.error(
        'Attempt to use provisioning JWT as a user JWT, this is absolutely not expected and should be considered a security threat. '
        'Rotate the JWT secret and deploy a new version of the application immediately',
      );
      throw const InvalidJwtException();
    }

    /// An API token's credential is an opaque `zonai_pat_...` string, never a
    /// JWT -- the `API_TOKEN` payload exists only so a *resolved* token
    /// survives the trip to the rules and operations workers. A signed one
    /// arriving as a bearer token is the worst of the three sentinels to
    /// accept, because it is the only one whose payload also carries the
    /// powers: an attacker holding the signing key (a leaked `jwtSecret`, or
    /// a retired one still live in `previousJwtSecrets` on purpose) would mint
    /// themselves an unscoped, never-expiring admin identity with no row in
    /// `_api_tokens` to revoke.
    if (Jwt.isApiTokenPayload(decoded)) {
      _logForgedApiTokenPayload();
      throw const InvalidJwtException();
    }

    Jwt appJwt;

    try {
      appJwt = Jwt.fromJson(decoded);
    } on Object {
      throw const InvalidJwtException();
    }

    return await _validateJwt(appJwt);
  }

  /// Turns a presented `zonai_pat_...` credential into the identity it names.
  ///
  /// One indexed read of `_api_tokens` on the SHA-256 of what was presented --
  /// the same cost `_validateJwt` already pays against `_jwt`, and through the
  /// query builder rather than the operations layer, because
  /// `TableOperations` refuses a `where` on a secret column
  /// ([SecretColumnFilterException]). That refusal is deliberate: strippable
  /// but filterable would make `startsWith` on a hash a blind oracle. It also
  /// means `/db` is structurally incapable of being the path a credential is
  /// resolved on, which is a good property to have for free.
  ///
  /// Unknown, revoked and expired all answer the same [InvalidJwtException].
  /// There is no oracle to protect here -- you have to already hold the secret
  /// to ask -- so the flat answer is for simplicity, not secrecy, and telling
  /// the three apart later is safe.
  Future<Jwt> _resolveApiToken(String presented) async {
    final normalized = ApiTokenSecret.normalize(presented);

    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    final rows = await db
        .select()
        .from(apiTokens)
        .where(apiTokens.tokenHash.equals(ApiTokenSecret.hash(normalized)));

    logger.trace('api_token_db_lookup', extra: {'found': rows.isNotEmpty});

    final row = rows.singleOrNull;
    if (row == null || row.isRevoked || row.isExpiredAt(clock.now())) {
      throw const InvalidJwtException();
    }

    // Bookkeeping, not authorization: awaited so a test can observe it, but
    // it cannot fail the request (see [_touchApiToken]).
    await _touchApiToken(row);

    return ApiTokenJwt(
      tokenId: row.id,
      name: row.name,
      scope: row.scope,
      claims: row.claims,
      boundTable: row.boundTable,
      boundUserId: switch (row.boundUserId) {
        final id? => UnknownId(id),
        null => null,
      },
      boundUser: await _boundUserRow(row),
      revokesAt: row.expiresAt,
    );
  }

  /// The auth row a bound token acts as, sanitized, so a rule reading
  /// `jwt.user['...']` sees what it would see for a signed-in session.
  ///
  /// Empty for an unbound token, which owns no rows -- and empty, rather than
  /// a failure, when the bound row has since been deleted: the scope still
  /// bounds what the token can reach, and every ownership rule comparing
  /// against `jwt.userId` now matches nothing, which is the right outcome for
  /// a token whose user is gone.
  Future<Map<String, Object?>> _boundUserRow(ApiTokenEntry row) async {
    final table = row.boundTable;
    final userId = row.boundUserId;
    if (table == null || userId == null) return const {};

    return await _boundUserRowFor(table: table, userId: userId);
  }

  /// Both bearer paths log identically, so a forged token is one greppable
  /// string wherever it is presented.
  void _logForgedApiTokenPayload() {
    logger.error(
      'Attempt to use an API-token payload as a bearer JWT. An API token is '
      'an opaque credential, never a signed token, so nothing zonai issues '
      'looks like this -- either the JWT signing key has leaked or a retired '
      'one is still in previousJwtSecrets. This is absolutely not expected '
      'and should be considered a security threat. Rotate the JWT secret and '
      'deploy a new version of the application immediately.',
    );
  }

  Future<Jwt> _validateJwt(Jwt jwt) async {
    // Worker sentinels are minted in-process, never parsed from a bearer
    // token (`_extractJwt` rejects both payload shapes before it gets here),
    // so their powers are not attacker-influenced and there is nothing to
    // re-derive.
    if (jwt is CronJwt || jwt is ProvisioningJwt) {
      return jwt;
    }

    // An [ApiTokenJwt] never arrives from a bearer JWT either (the check in
    // [_extractJwt] above refuses that payload outright); it is built here,
    // in-process, from a row this method would only re-read. Its revocation
    // record is that row, not `_jwt`, and its admin powers come from the same
    // row -- so [_withServerDerivedAdmin] has nothing to derive from and would
    // rebuild it as a plain [Jwt], dropping both the type and the scope every
    // downstream check depends on.
    if (jwt is ApiTokenJwt) {
      return jwt;
    }

    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    final jwtRecord = await db
        .select()
        .from(jwts)
        .where(jwts.id.equals(jwt.jwtId));
    logger.trace('jwt_db_lookup', extra: {'found': jwtRecord.isNotEmpty});

    if (jwtRecord.isEmpty) {
      throw const JwtRecordNotFoundException();
    }

    return await _withServerDerivedAdmin(jwt);
  }

  /// Replaces the token's `admin` claim with the one the server derives, so a
  /// tampered claim is inert even if the signing key leaks.
  ///
  /// The claim used to be trusted verbatim: `Jwt.fromJson` reads `admin` off
  /// the wire, and nothing downstream re-checked it. Anyone who could sign a
  /// token -- which, before `AppConfig.validate()` grew a strength check, meant
  /// anyone who could guess a secret like `jwt` -- could flip `isAdmin` on
  /// their own session and be honoured. Forging the rest was already blocked
  /// ([_validateJwt] requires a real `_jwt` row), so the flag was the whole
  /// exploit.
  ///
  /// Admin is a property of the *table*, declared by mixing `AsAdmin` into its
  /// schema, so the authoritative value is the registered schema's -- not
  /// anything stored per user, and not anything the token can carry. That also
  /// means a demotion takes effect on the next request rather than at token
  /// expiry: remove `AsAdmin` and redeploy, and every outstanding token for
  /// that table stops being an admin token immediately.
  Future<Jwt> _withServerDerivedAdmin(Jwt jwt) async {
    final status = await _tableAdminStatus(jwt.table);

    // Only an ESCALATION is worth a line in the log: a claim asserting more
    // than the schema grants is a token nobody here could have issued.
    //
    // Not "any disagreement". `Jwt.fromJson` normalises every non-admin token
    // to `canEdit: null` while the schema reports `false`, so a disagreement
    // check would fire on every ordinary user request — and an alert that
    // fires constantly is an alert nobody reads, which is worse than none.
    final claimsMoreThanGranted =
        (jwt.admin.isAdmin && !status.isAdmin) ||
        (jwt.admin.canEdit == true && !status.canEdit);

    if (claimsMoreThanGranted) {
      logger.warn(
        'JWT for table "${jwt.table}" claims admin powers the schema does not '
        'grant (claimed isAdmin: ${jwt.admin.isAdmin}, canEdit: '
        '${jwt.admin.canEdit}; schema isAdmin: ${status.isAdmin}, canEdit: '
        '${status.canEdit}). The claim is being ignored. Zonai never issues a '
        'token like this, so either the signing key has leaked or a retired '
        'one is still in previousJwtSecrets — rotate it.',
        prefix: _prefix,
      );
    }

    return Jwt(
      userId: jwt.userId,
      table: jwt.table,
      jwtId: jwt.jwtId,
      expiresAt: jwt.expiresAt,
      user: jwt.user,
      claims: jwt.claims,
      admin: (isAdmin: status.isAdmin, canEdit: status.canEdit),
    );
  }

  /// Memoised: the schema cannot change without restarting the process, and
  /// this is consulted on every authenticated request.
  Future<({bool isAdmin, bool canEdit})> _tableAdminStatus(String table) async {
    if (_adminStatusCache[table] case final cached?) {
      return cached;
    }

    final response = await _dispatchOperation<TableAdminStatusResponse>(
      GetTableAdminStatusRequest(table: table),
    );

    return _adminStatusCache[table] = (
      isAdmin: response.isAdmin,
      canEdit: response.canEdit,
    );
  }

  Future<void> _requireAuthTableAccess(
    String table,
    AuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);

    final response = await _dispatchRules<AuthTableRulesResponse>(
      AuthTableRulesRequest(
        table: table,
        jwt: jwt,
        authType: switch (payload) {
          PasswordAuthPayload() => .password,
          SendOtpAuthPayload() || VerifyOtpAuthPayload() => .otp,
          SendMagicLinkAuthPayload() ||
          VerifyMagicLinkAuthPayload() => .magicLink,
          ResetPasswordAuthPayload() => .password,
          ConfirmResetPasswordAuthPayload() => .password,
          StartOAuthAuthPayload() ||
          CompleteOAuthAuthPayload() ||
          NativeOAuthAuthPayload() => .oauth,
        },
      ),
    );

    if (response case AuthTableRulesResponse(canAuthenticate: true)) {
      return;
    }

    throw AuthTableNotFoundException(table: table);
  }

  Future<String?> _emailFromJwt({
    required String table,
    required Jwt jwt,
  }) async {
    if (jwt.table != table) {
      return null;
    }

    final emailColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .email),
    );

    return switch (jwt.user[emailColumn.name]) {
      final String email => email,
      _ => null,
    };
  }

  Future<void> _requireAdminOrOwnEmail({
    required String table,
    required String email,
    required bool allowUnauthenticated,
    Jwt? jwt,
  }) async {
    if (jwt == null) {
      if (allowUnauthenticated) {
        return;
      }
      throw const AuthEmailForbiddenException(
        reason: 'Authentication is required to send this email',
      );
    }

    final validated = await _validateJwt(jwt);

    if (validated.admin.isAdmin) {
      return;
    }

    final userEmail = await _emailFromJwt(table: table, jwt: validated);
    if (userEmail != null && userEmail.toLowerCase() == email.toLowerCase()) {
      return;
    }

    throw const AuthEmailForbiddenException(
      reason: "Cannot send email to another user's email address",
    );
  }
}
