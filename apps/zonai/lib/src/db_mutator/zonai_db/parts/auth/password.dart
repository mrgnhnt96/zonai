part of zonai_db;

extension _PasswordX on ZonaiDb {
  Future<_AuthResult> _authenticatePassword(
    String table,
    PasswordAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(table: table, payload: payload);

    if (!hasAuthRecord) {
      if (isAdmin) {
        throw UserNotFoundAuthException(table: table);
      }

      return await _signUpWithPassword(table, payload);
    }

    return await _signInWithPassword(table, payload);
  }

  Future<_AuthResult> _signInWithPassword(
    String table,
    PasswordAuthPayload payload,
  ) async {
    if (payload.jwt != null) {
      throw const AlreadyAuthenticatedException();
    }

    await _requireAuthTableAccess(table, payload);
    await _requireAuthRecordAccess(table, .signIn, payload);

    final user = await _passwordRecord(
      table: table,
      payload: payload,
      rawPassword: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
    );

    if (user == null) {
      throw UserNotFoundAuthException(table: table);
    }

    final (jwt, token) = await _createJwt(table, user);

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onSignIn(table: table, object: user, jwt: jwt),
    );

    await _executeEffects();

    return (user: user, jwt: token);
  }

  Future<_AuthResult> _signUpWithPassword(
    String table,
    PasswordAuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);
    await _requireAuthTableAccess(table, payload);
    await _requireAuthRecordAccess(table, .signUp, payload);

    final hashedPassword = await _hashPassword.hash(
      password: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
    );

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        table: table,
        jwt: jwt,
        payload: PasswordAuthOperationPayload.save(
          email: payload.email,
          passwordHash: hashedPassword,
          object: payload.object,
        ),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));

    if (error != null || result == null) {
      throw error ?? AuthFailedException(cause: 'Failed to create user');
    }

    final user = await _sanitizeRow(table, result.rows.single.toMap());

    logger.verbose('Created: ${user}', prefix: _prefix);

    final (newJwt, token) = await _createJwt(table, user);

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onSignUp(table: table, object: user, jwt: newJwt),
    );

    return (user: user, jwt: token);
  }
}
