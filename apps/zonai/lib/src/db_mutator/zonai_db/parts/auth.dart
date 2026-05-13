part of zonai_db;

typedef _AuthResult = ({Map<String, Object?> user, String jwt});

extension _AuthX on ZonaiDb {
  /// Signs in a user if the credentials are valid
  ///
  /// Signs up a user if the record does not exist
  Future<_Result<_AuthResult>> _authenticate(
    String collection,
    AuthPayload payload,
  ) async {
    await _requireAuthCollectionAccess(collection, payload);
    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: payload,
    );

    if (!hasAuthRecord) {
      return await _signUp(collection, payload);
    }

    return await _signIn(collection, payload);
  }

  // TODO(mrgnhnt): Make this configurable
  static const jwtPepper = 'jwt_pepper';

  Future<_Result<_AuthResult>> _signIn(
    String collection,
    AuthPayload payload,
  ) async {
    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, .signIn, payload);

    final user = await _authRecord(
      collection: collection,
      payload: payload,
      rawPassword: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
    );

    if (user == null) {
      throw StateError('User not found, cannot sign in');
    }

    {
      final onSignIn = await _extensions.send(
        AuthExtensionRequest.onSignIn(collection: collection, object: user),
      );
    }

    final jwtId = JwtId.generate();
    // TODO(mrgnhnt): Get user ID from the user object
    final userId = user['id'] as String;

    final jwtObject = await _jwt.generate(
      AppJwt.create(
        userId: userId,
        collection: collection,
        jwtId: jwtId.value,
        expiresIn: const Duration(days: 365),
        claims: {},
      ),
    );

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    await db.insert(into: jwts).values([
      JwtCollection(id: jwtId, userId: UnknownId(userId)),
    ]);

    return (null, (user: user, jwt: jwtObject));
  }

  Future<_Result<_AuthResult>> _signUp(
    String collection,
    AuthPayload payload,
  ) async {
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
        payload: PasswordAuthOperationPayload.save(
          email: payload.email,
          passwordHash: hashedPassword,
          object: payload.object,
        ),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));

    if (error != null || result == null) {
      logger.trace('Failed to create user: $error', prefix: _prefix);
      return (error ?? 'Failed', null);
    }

    final user = result.rows.single.toMap();

    // TODO(mrgnhnt): Send object to extension to sanitize
    final passwordColumn = await _operations.send(
      GetPasswordColumnNameRequest(collection: collection),
    );

    if (passwordColumn is! PasswordColumnNameResponse) {
      logger.trace('Failed to get password column name', prefix: _prefix);
      return (null, null);
    }

    user.remove(passwordColumn.columnName);

    logger.verbose('Created: ${user}', prefix: _prefix);

    {
      final onSignUp = await _extensions.send(
        AuthExtensionRequest.onSignUp(collection: collection, object: user),
      );
    }

    final jwtId = JwtId.generate();
    // TODO(mrgnhnt): Get user ID from the user object
    final userId = user['id'] as String;

    final jwtObject = await _jwt.generate(
      AppJwt.create(
        userId: userId,
        collection: collection,
        jwtId: jwtId.value,
        expiresIn: const Duration(days: 365),
        claims: {},
      ),
    );

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    await db.insert(into: jwts).values([
      JwtCollection(id: jwtId, userId: UnknownId(userId)),
    ]);

    return (null, (user: user, jwt: jwtObject));
  }

  Future<void> _logout(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw StateError('Invalid JWT');
    }

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    final result = await db
        .delete(from: jwts)
        .where(jwts.id.equals(appJwt.jwtId))
        .returning();

    if (result.isEmpty) {
      logger.verbose('No JWT record found', prefix: _prefix);
      return;
    }

    logger.verbose('Logged out: ${appJwt.userId}', prefix: _prefix);
  }

  Future<void> _logoutAll(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw StateError('Invalid JWT');
    }

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    final results = await db
        .delete(from: jwts)
        .where(jwts.userId.equals(appJwt.userId))
        .returning();

    if (results.isEmpty) {
      logger.verbose('No JWT records found', prefix: _prefix);
      return;
    }

    logger.verbose(
      'Logged out all: ${appJwt.userId} (${results.length})',
      prefix: _prefix,
    );
  }
}
