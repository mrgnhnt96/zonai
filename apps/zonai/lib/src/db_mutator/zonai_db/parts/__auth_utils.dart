part of zonai_db;

extension _AuthUtilsX on ZonaiDb {
  Future<Map<String, Object?>?> _passwordRecord({
    required String collection,
    required PasswordAuthPayload payload,
    required String rawPassword,
  }) async {
    final jwt = await _extractJwt(payload);

    final response = await _operations.send<PerformOperationResponse>(
      ViewAuthOperationRequest(
        collection: collection,
        jwt: jwt,
        payload: PasswordAuthOperationPayload.get(email: payload.email),
      ),
    );

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw StateError('Failed to authenticate: $error');
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) {
      return null;
    }

    final passwordColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: collection, columnName: .password),
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
      throw StateError('Invalid password or email');
    }

    return await _sanitizeRow(collection, user);
  }

  Future<Map<String, Object?>?> _authRecord({
    required String collection,
    required String email,
    bool sanitize = true,
  }) async {
    final response = await _operations.send<PerformOperationResponse>(
      ViewAuthOperationRequest(
        collection: collection,
        jwt: null,
        payload: OtpAuthOperationPayload.get(email: email),
      ),
    );

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw StateError('Failed to authenticate: $error');
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) {
      return null;
    }

    if (!sanitize) {
      return user;
    }

    return await _sanitizeRow(collection, user);
  }

  Future<bool> _hasAuthRecord({
    required String collection,
    required AuthPayload payload,
  }) async {
    final jwt = await _extractJwt(payload);

    final response = await _operations.send<PerformOperationResponse>(
      ViewAuthOperationRequest(
        collection: collection,
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
      throw StateError('Failed to authenticate: $error');
    }

    final user = result?.rows.singleOrNull?.toMap();
    return user != null;
  }

  Future<void> _requireAuthRecordAccess(
    String collection,
    AuthOperation operation,
    AuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);

    final response = await _rules.send<AuthRecordRulesResponse>(
      AuthRecordRulesRequest(
        collection: collection,
        jwt: jwt,
        operation: operation,
        authType: payload.authType,
      ),
    );

    if (response case AuthRecordRulesResponse(canAccess: true)) {
      return;
    }

    throw StateError(
      'User permissions are restricted. Action: "${operation.name}" on collection: "$collection"',
    );
  }

  Future<Jwt?> _extractJwt(JwtPayload payload) async {
    final jwt = payload.jwt;

    if (jwt == null) {
      return null;
    }

    final decoded = await _jwt.verify(jwt);
    if (decoded == null) {
      throw StateError('Invalid JWT');
    }

    Jwt appJwt;

    try {
      appJwt = Jwt.fromJson(decoded);
    } on Object {
      throw StateError('Invalid JWT');
    }

    return await _validateJwt(appJwt);
  }

  Future<Jwt> _validateJwt(Jwt jwt) async {
    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    final jwtRecord = await db
        .select()
        .from(jwts)
        .where(jwts.id.equals(jwt.jwtId));

    if (jwtRecord.isEmpty) {
      throw StateError('JWT record not found');
    }

    return jwt;
  }

  Future<void> _requireAuthCollectionAccess(
    String collection,
    AuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);

    final response = await _rules.send<AuthCollectionRulesResponse>(
      AuthCollectionRulesRequest(
        collection: collection,
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

    if (response case AuthCollectionRulesResponse(canAuthenticate: true)) {
      return;
    }

    throw StateError('Cannot authenticate for collection: $collection');
  }

  Future<String?> _emailFromJwt({
    required String collection,
    required Jwt jwt,
  }) async {
    if (jwt.collection != collection) {
      return null;
    }

    final emailColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: collection, columnName: .email),
    );

    return switch (jwt.user[emailColumn.name]) {
      final String email => email,
      _ => null,
    };
  }

  Future<void> _requireAdminOrOwnEmail({
    required String collection,
    required String email,
    required bool allowUnauthenticated,
    Jwt? jwt,
  }) async {
    if (jwt == null) {
      if (allowUnauthenticated) {
        return;
      }
      throw StateError('Authentication is required to send this email');
    }

    final validated = await _validateJwt(jwt);

    if (validated.admin.isAdmin) {
      return;
    }

    final userEmail = await _emailFromJwt(
      collection: collection,
      jwt: validated,
    );
    if (userEmail != null && userEmail.toLowerCase() == email.toLowerCase()) {
      return;
    }

    throw StateError('Cannot send email to another user\'s email address');
  }
}
