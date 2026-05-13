part of zonai_db;

extension _AuthUtilsX on ZonaiDb {
  Future<Map<String, Object?>?> _authRecord({
    required String collection,
    required AuthPayload payload,
    required String rawPassword,
  }) async {
    final response = await _operations.send(
      ViewAuthOperationRequest(
        collection: collection,
        payload: switch (payload) {
          PasswordAuthPayload() => PasswordAuthOperationPayload.get(
            email: payload.email,
          ),
        },
      ),
    );

    if (response is! PerformOperationResponse) {
      throw StateError('Failed to authenticate');
    }

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw StateError('Failed to authenticate: $error');
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) {
      return null;
    }

    final passwordColumn = await _operations.send(
      GetPasswordColumnNameRequest(collection: collection),
    );
    if (passwordColumn is! PasswordColumnNameResponse) {
      logger.trace('Failed to get password column name', prefix: _prefix);
      return null;
    }

    // TODO(mrgnhnt): Send object to extension to sanitize
    final passwordHash = user.remove(passwordColumn.columnName)!;
    if (passwordHash is! String) {
      logger.trace('Password hash not found', prefix: _prefix);
      return null;
    }

    final passwordsMatch = await _hashPassword.verify(
      rawPassword: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
      passwordHash: passwordHash,
    );

    if (!passwordsMatch) {
      throw StateError('Invalid password or email');
    }

    return user;
  }

  Future<bool> _hasAuthRecord({
    required String collection,
    required AuthPayload payload,
  }) async {
    final response = await _operations.send(
      ViewAuthOperationRequest(
        collection: collection,
        payload: switch (payload) {
          PasswordAuthPayload() => PasswordAuthOperationPayload.get(
            email: payload.email,
          ),
        },
      ),
    );

    if (response is! PerformOperationResponse) {
      throw StateError('Failed to authenticate');
    }

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
    final response = await _rules.send(
      AuthRecordRulesRequest(
        collection: collection,
        operation: operation,
        authType: payload.authType,
      ),
    );

    if (response case AuthRecordRulesResponse(canAccess: true)) {
      return;
    }

    throw StateError('User does not have access to $operation on $collection');
  }

  Future<AppJwt?> _extractJwt(JwtPayload payload) async {
    final jwt = payload.jwt;

    if (jwt == null) {
      return null;
    }

    final decoded = await const Jwt(jwtPepper: _appPepper).verify(jwt);
    if (decoded == null) {
      throw StateError('Invalid JWT');
    }

    final appJwt = AppJwt.fromJson(decoded);
    logger.verbose('Extracted JWT: ${appJwt}', prefix: _prefix);

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    final jwtRecord = await db
        .select()
        .from(jwts)
        .where(jwts.id.equals(appJwt.jwtId));
    if (jwtRecord.isEmpty) {
      throw StateError('JWT record not found');
    }

    return appJwt;
  }

  Future<void> _requireAuthCollectionAccess(
    String collection,
    AuthPayload payload,
  ) async {
    final response = await _rules.send(
      AuthCollectionRulesRequest(
        collection: collection,
        authType: switch (payload) {
          PasswordAuthPayload() => .password,
        },
      ),
    );

    if (response case AuthCollectionRulesResponse(canAuthenticate: true)) {
      return;
    }

    throw StateError('Cannot authenticate for collection: $collection');
  }
}
