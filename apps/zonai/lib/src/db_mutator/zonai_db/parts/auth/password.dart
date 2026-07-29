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
    logger.setTraceProps({'op': 'sign_in', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      if (payload.jwt != null) {
        throw const AlreadyAuthenticatedException();
      }

      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'row_access';
      await _requireAuthRecordAccess(table, .signIn, payload);
      logger.trace('row_access');

      step = 'password_verify';
      final user = await _passwordRecord(
        table: table,
        payload: payload,
        rawPassword: switch (payload) {
          PasswordAuthPayload() => payload.password,
        },
      );
      logger.trace('password_verify', extra: {'match': user != null});

      if (user == null) {
        throw UserNotFoundAuthException(table: table);
      }

      step = 'jwt_create';
      final (jwt, token) = await _createJwt(table, user);
      logger.trace('jwt_create');

      step = 'ext_hook';
      await _extensions.send<NoActionExtensionResponse>(
        AuthExtensionRequest.onSignIn(table: table, object: user, jwt: jwt),
      );
      logger.trace('ext_hook');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return (user: user, jwt: token);
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<_AuthResult> _signUpWithPassword(
    String table,
    PasswordAuthPayload payload,
  ) async {
    logger.setTraceProps({'op': 'sign_up', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'row_access';
      await _requireAuthRecordAccess(table, .signUp, payload);
      logger.trace('row_access');

      step = 'password_hash';
      final hashedPassword = await _hashPassword.hash(
        password: switch (payload) {
          PasswordAuthPayload() => payload.password,
        },
      );
      logger.trace('password_hash');

      step = 'sql_build';
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
      logger.trace('sql_build');

      step = 'sql_execute';
      final (error, result) = await _execute((
        operation.query,
        operation.values,
      ));
      logger.trace('sql_execute');

      if (error != null || result == null) {
        throw error ?? AuthFailedException(cause: 'Failed to create user');
      }

      step = 'sanitize';
      final user = await _sanitizeRow(table, result.rows.single.toMap());
      logger.verbose('Created: ${user}', prefix: _prefix);
      logger.trace('sanitize');

      step = 'jwt_create';
      final (newJwt, token) = await _createJwt(table, user);
      logger.trace('jwt_create');

      step = 'ext_hook';
      await _extensions.send<NoActionExtensionResponse>(
        AuthExtensionRequest.onSignUp(table: table, object: user, jwt: newJwt),
      );
      logger.trace('ext_hook');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return (user: user, jwt: token);
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }
}
