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

      case SendMagicLinkAuthPayload():
        await _sendMagicLink(collection, payload, isAdmin: isAdmin);
        return null;

      case VerifyMagicLinkAuthPayload():
        return await _verifyMagicLink(collection, payload, isAdmin: isAdmin);
    }
  }

  Future<_AuthResult?> _authenticateAdmin(AuthPayload payload) async {
    final collection = await _adminCollectionFor(payload.authType);

    return await _authenticate(collection, payload, isAdmin: true);
  }

  Future<String> _adminCollectionFor(AuthType authType) async {
    final authCollections = await _operations.send<AdminCollectionsResponse>(
      GetAdminCollectionsOperationRequest(),
    );

    StateError? lastError;
    for (final (collection, authTypes) in authCollections.collections) {
      if (!authTypes.contains(authType)) {
        continue;
      }

      try {
        return collection;
      } on StateError catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        StateError('No $authType sign-in is configured for admin');
  }

  Future<_AuthResult> _signIntoCollection({
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

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onSignIn(
        collection: collection,
        object: user,
        jwt: newJwt,
      ),
    );

    await _executeEffects();

    return (user: user, jwt: token);
  }

  Future<List<AuthType>> _adminSupportedAuthTypes() async {
    final authCollections = await _operations.send<AdminCollectionsResponse>(
      GetAdminCollectionsOperationRequest(),
    );

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
    final userIdColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: collection, columnName: .id),
    );

    final userId = user[userIdColumn.name] as String;

    final preJwt = Jwt.create(
      userId: userId,
      collection: collection,
      user: user,
      jwtId: jwtId.value,
      expiresIn: const Duration(days: 365),
      claims: {},
    );

    final claims = await _operations.send<ClaimsResponse>(
      GetClaimsOperationRequest(collection: collection, jwt: preJwt),
    );

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

    final db = await open();

    await db.insert(into: jwts).values([
      JwtEntry(
        id: JwtId(jwt.jwtId),
        userId: UnknownId(jwt.userId),
        expiresAt: jwt.expiresAt,
      ),
    ]);

    return (jwt, token);
  }
}
