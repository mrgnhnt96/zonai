part of zonai_db;

extension _PasswordX on ZonaiDb {
  Future<_AuthResult> _authenticatePassword(
    String collection,
    PasswordAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: payload,
    );

    if (!hasAuthRecord) {
      if (isAdmin) {
        throw StateError(
          'Cannot create an Admin account without an existing account',
        );
      }

      return await _signUpWithPassword(collection, payload);
    }

    return await _signInWithPassword(collection, payload);
  }

  Future<_AuthResult> _signInWithPassword(
    String collection,
    PasswordAuthPayload payload,
  ) async {
    if (payload.jwt != null) {
      throw StateError('User already authenticated');
    }

    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, .signIn, payload);

    final user = await _passwordRecord(
      collection: collection,
      payload: payload,
      rawPassword: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
    );

    if (user == null) {
      throw StateError('User not found, cannot sign in');
    }

    final (jwt, token) = await _createJwt(collection, user);

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onSignIn(
        collection: collection,
        object: user,
        jwt: jwt,
      ),
    );

    await _executeEffects();

    return (user: user, jwt: token);
  }

  Future<_AuthResult> _signUpWithPassword(
    String collection,
    PasswordAuthPayload payload,
  ) async {
    final jwt = await _extractJwt(payload);
    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, .signUp, payload);

    final hashedPassword = await _hashPassword.hash(
      password: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
    );

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        collection: collection,
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
      throw error ?? StateError('Failed to create user');
    }

    final user = await _sanitizeRow(collection, result.rows.single.toMap());

    logger.verbose('Created: ${user}', prefix: _prefix);

    final (newJwt, token) = await _createJwt(collection, user);

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onSignUp(
        collection: collection,
        object: user,
        jwt: newJwt,
      ),
    );

    return (user: user, jwt: token);
  }
}
