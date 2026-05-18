part of zonai_db;

typedef _AuthResult = ({Map<String, Object?> user, String jwt});

extension _AuthX on ZonaiDb {
  /// Signs in a user if the credentials are valid
  ///
  /// Signs up a user if the record does not exist
  Future<_AuthResult> _authenticate(
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

  Future<_AuthResult> _signIn(String collection, AuthPayload payload) async {
    if (payload.jwt != null) {
      throw StateError('User already authenticated');
    }

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

    final (jwt, token) = await _createJwt(collection, user);

    await _extensions.send(
      AuthExtensionRequest.onSignIn(
        collection: collection,
        object: user,
        jwt: jwt,
      ),
    );

    await _executeEffects();

    return (user: user, jwt: token);
  }

  Future<_AuthResult> _adminSignIn(AuthPayload payload) async {
    if (payload.jwt != null) {
      throw StateError('User already authenticated');
    }

    final authCollections = await _operations.send(
      GetAdminCollectionsOperationRequest(),
    );
    if (authCollections is! AdminCollectionsResponse) {
      throw StateError('Failed to get admin collections');
    }

    for (final collection in authCollections.collections) {
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

      final (jwt, token) = await _createJwt(collection, user);

      await _extensions.send(
        AuthExtensionRequest.onSignIn(
          collection: collection,
          object: user,
          jwt: jwt,
        ),
      );

      await _executeEffects();

      return (user: user, jwt: token);
    }

    throw StateError('Unknown or invalid admin credentials');
  }

  Future<(Jwt, String)> _createJwt(
    String collection,
    Map<String, Object?> user,
  ) async {
    final jwtId = JwtId.generate();
    final userIdColumn = await _operations.send(
      GetColumnNameRequest(collection: collection, columnName: .id),
    );
    if (userIdColumn is! ColumnNameResponse) {
      throw StateError('Failed to get user ID column name');
    }

    final userId = user[userIdColumn.name] as String;

    final preJwt = Jwt.create(
      userId: userId,
      collection: collection,
      user: user,
      jwtId: jwtId.value,
      expiresIn: const Duration(days: 365),
      claims: {},
    );

    final claims = await _operations.send(
      GetClaimsOperationRequest(collection: collection, jwt: preJwt),
    );

    if (claims is! ClaimsResponse) {
      throw StateError('Failed to get claims');
    }

    final jwt = Jwt(
      userId: preJwt.userId,
      collection: preJwt.collection,
      jwtId: preJwt.jwtId,
      expiresAt: preJwt.expiresAt,
      user: preJwt.user,
      claims: claims.claims.toJson(),
      admin: (isAdmin: claims.isAdmin, canEdit: claims.canEdit),
    );

    final token = await _jwt.generate(jwt);

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    await db.insert(into: jwts).values([
      JwtEntry(id: JwtId(jwt.jwtId), userId: UnknownId(jwt.userId)),
    ]);

    return (jwt, token);
  }

  Future<_AuthResult> _signUp(String collection, AuthPayload payload) async {
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

    await _extensions.send(
      AuthExtensionRequest.onSignUp(
        collection: collection,
        object: user,
        jwt: newJwt,
      ),
    );

    return (user: user, jwt: token);
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

    await _extensions.send(
      AuthExtensionRequest.onLogout(
        collection: appJwt.collection,
        object: appJwt.user,
        jwt: appJwt,
      ),
    );

    await _executeEffects();
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
