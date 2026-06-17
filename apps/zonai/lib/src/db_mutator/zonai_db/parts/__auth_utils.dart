part of zonai_db;

extension _AuthUtilsX on ZonaiDb {
  Future<Map<String, Object?>?> _passwordRecord({
    required String table,
    required PasswordAuthPayload payload,
    required String rawPassword,
  }) async {
    final jwt = await _extractJwt(payload);

    final response = await _operations.send<PerformOperationResponse>(
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

    final passwordColumn = await _operations.send<ColumnNameResponse>(
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
    final response = await _operations.send<PerformOperationResponse>(
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

    final response = await _operations.send<PerformOperationResponse>(
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

    final response = await _rules.send<AuthRowRulesResponse>(
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

    try {
      return Jwt.fromJson(decoded);
    } on Object {
      throw const InvalidJwtException();
    }
  }

  Future<Jwt?> _extractJwt(JwtPayload payload) async {
    final jwt = payload.jwt;

    if (jwt == null) {
      return null;
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

    Jwt appJwt;

    try {
      appJwt = Jwt.fromJson(decoded);
    } on Object {
      throw const InvalidJwtException();
    }

    return await _validateJwt(appJwt);
  }

  Future<Jwt> _validateJwt(Jwt jwt) async {
    if (jwt is CronJwt) {
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

    return jwt;
  }

  Future<void> _requireAuthTableAccess(
    String table,
    AuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);

    final response = await _rules.send<AuthTableRulesResponse>(
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

    final emailColumn = await _operations.send<ColumnNameResponse>(
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
