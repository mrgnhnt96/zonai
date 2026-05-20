part of zonai_db;

typedef _AuthResult = ({Map<String, Object?> user, String jwt});

extension _AuthX on ZonaiDb {
  /// Signs in a user if the credentials are valid
  ///
  /// Signs up a user if the record does not exist
  Future<_AuthResult?> _authenticate(
    String collection,
    AuthPayload payload, {
    bool isAdmin = false,
  }) async {
    switch (payload) {
      case PasswordAuthPayload():
        return await _authenticatePassword(
          collection,
          payload,
          isAdmin: isAdmin,
        );

      case SendOtpAuthPayload():
        await _sendOtp(collection, payload, isAdmin: isAdmin);
        return null;

      case VerifyOtpAuthPayload():
        return await _verifyOtp(collection, payload, isAdmin: isAdmin);
    }
  }

  Future<_AuthResult?> _authenticateAdmin(AuthPayload payload) async {
    final collection = await _adminCollectionFor(payload.authType);

    return await _authenticate(collection, payload, isAdmin: true);
  }

  Future<void> _sendOtp(
    String collection,
    SendOtpAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: payload,
    );

    if (isAdmin) {
      if (!hasAuthRecord) {
        throw StateError(
          'Cannot create an Admin account without an existing account',
        );
      }
    }

    final operation = switch (hasAuthRecord) {
      true => AuthOperation.signIn,
      false => AuthOperation.signUp,
    };

    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, operation, payload);

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    // must wait 1 minute before sending a new OTP
    final lastOtp = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.target.equals(payload.email) &
              authChallenges.collection.equals(collection),
        )
        .limit(1);

    if (lastOtp.isNotEmpty) {
      final lastOtpCreatedAt = lastOtp.first.createdAt;

      if (lastOtpCreatedAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw StateError('Must wait 1 minute before sending a new OTP');
      }
    }

    // expire all old opts for this email
    await db
        .delete(from: authChallenges)
        .where(
          authChallenges.target.equals(payload.email) &
              authChallenges.collection.equals(collection),
        );

    final expiresIn = const Duration(minutes: 10);
    final otp = switch (kIsCompiled) {
      false => '123456',
      true => Random.secure().nextInt(1000000).toString().padLeft(6, '0'),
    };
    final hashedOtp = await _hashPassword.hash(password: otp);

    await db.insert(into: authChallenges).values([
      AuthChallenge.otp(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(expiresIn),
        metadata: payload.object,
        otpHash: hashedOtp,
        target: payload.email,
        collection: collection,
      ),
    ]);

    courier.send(
      SendOtpEmail(
        to: EmailAddress(address: payload.email),
        collection: collection,
        isResend: lastOtp.isNotEmpty,
        code: otp,
        expiresIn: expiresIn,
        variables: payload.object,
      ),
    );
  }

  Future<String> _adminCollectionFor(AuthType authType) async {
    final authCollections = await _operations.send(
      GetAdminCollectionsOperationRequest(),
    );
    if (authCollections is! AdminCollectionsResponse) {
      throw StateError('Failed to get admin collections');
    }

    StateError? lastError;
    for (final (collection, authTypes) in authCollections.collections) {
      if (!authTypes.contains(AuthType.otp)) {
        continue;
      }

      try {
        return collection;
      } on StateError catch (error) {
        lastError = error;
      }
    }

    throw lastError ?? StateError('No OTP sign-in is configured for admin');
  }

  Future<_AuthResult> _verifyOtp(
    String collection,
    VerifyOtpAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: payload,
    );

    if (isAdmin) {
      if (!hasAuthRecord) {
        throw StateError(
          'Cannot create an Admin account without an existing account',
        );
      }
    }

    final operation = switch (hasAuthRecord) {
      true => AuthOperation.signIn,
      false => AuthOperation.signUp,
    };

    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, operation, payload);

    await open();
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    final challenges = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.target.equals(payload.email) &
              authChallenges.collection.equals(collection),
        )
        .limit(1);

    if (challenges.isEmpty) {
      throw StateError('Invalid or expired code');
    }

    final challenge = challenges.first;
    if (challenge.type != .otp) {
      throw StateError('Invalid or expired code');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw StateError('Code expired');
    }

    final otpHash = challenge.otpHash;
    if (otpHash == null) {
      throw StateError('Invalid or expired code');
    }

    final codeMatches = await _hashPassword.verify(
      rawPassword: payload.code,
      passwordHash: otpHash,
    );
    if (!codeMatches) {
      throw StateError('Invalid or expired code');
    }

    await db
        .delete(from: authChallenges)
        .where(authChallenges.id.equals(challenge.id.value));

    if (hasAuthRecord) {
      return await _signInWithOtp(
        collection: collection,
        email: payload.email,
        jwt: payload.jwt,
      );
    }

    return await _signUpWithOtp(
      collection,
      email: payload.email,
      object: challenge.metadata,
      jwt: payload.jwt,
    );
  }

  Future<_AuthResult> _signInWithOtp({
    required String collection,
    required String email,
    required String? jwt,
  }) async {
    if (jwt != null) {
      throw StateError('User already authenticated');
    }

    final user = await _authRecord(collection: collection, email: email);
    if (user == null) {
      throw StateError('User not found, cannot sign in');
    }

    final (newJwt, token) = await _createJwt(collection, user);

    await _extensions.send(
      AuthExtensionRequest.onSignIn(
        collection: collection,
        object: user,
        jwt: newJwt,
      ),
    );

    await _executeEffects();

    return (user: user, jwt: token);
  }

  Future<_AuthResult> _signUpWithOtp(
    String collection, {
    required String email,
    Map<String, Object?>? object,
    String? jwt,
  }) async {
    final appJwt = await _extractJwt(
      SendOtpAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthCollectionAccess(
      collection,
      SendOtpAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthRecordAccess(
      collection,
      .signUp,
      SendOtpAuthPayload(email: email, object: object, jwt: jwt),
    );

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        collection: collection,
        jwt: appJwt,
        payload: OtpAuthOperationPayload.save(
          email: email,
          object: {...?object},
        ),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));

    if (error != null || result == null) {
      throw error ?? StateError('Failed to create user');
    }

    final user = await _sanitizeRow(collection, result.rows.single.toMap());

    logger.verbose('Created user using OTP', prefix: _prefix);

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

      return await _signUp(collection, payload);
    }

    return await _signIn(collection, payload);
  }

  Future<_AuthResult> _signIn(
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

  Future<List<AuthType>> _adminSupportedAuthTypes() async {
    final authCollections = await _operations.send(
      GetAdminCollectionsOperationRequest(),
    );
    if (authCollections is! AdminCollectionsResponse) {
      throw StateError('Failed to get admin collections');
    }

    final types = <AuthType>{};
    for (final (_, authTypes) in authCollections.collections) {
      types.addAll(authTypes);
    }

    final sorted = types.toList()..sort((a, b) => a.name.compareTo(b.name));
    return sorted;
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
      JwtEntry(
        id: JwtId(jwt.jwtId),
        userId: UnknownId(jwt.userId),
        expiresAt: jwt.expiresAt,
      ),
    ]);

    return (jwt, token);
  }

  Future<_AuthResult> _signUp(
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
