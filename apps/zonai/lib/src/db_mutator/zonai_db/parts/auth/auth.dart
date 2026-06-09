part of zonai_db;

typedef _AuthResult = ({Map<String, Object?> user, String jwt});

extension _AuthX on ZonaiDb {
  Future<_AuthResult?> _refreshToken(String token) async {
    logger.setTraceProps({'op': 'auth', 'table': 'refresh'});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final oldJwt = await _extractJwt(JwtPayload(jwt: token));
      logger.trace('jwt_extract');
      if (oldJwt == null) {
        throw const InvalidJwtException();
      }

      final emailColumn = await _operations.send<ColumnNameResponse>(
        GetColumnNameRequest(table: oldJwt.table, columnName: .email),
      );

      final email = switch (oldJwt.user[emailColumn.name]) {
        final String email => email,
        _ => throw EmailNotFoundAuthException(table: oldJwt.table),
      };

      step = 'sign_in';
      final result = await _signIntoCollection(
        table: oldJwt.table,
        email: email,
        jwt: null,
        extensionStep: .onRefresh,
      );
      logger.trace('sign_in');

      step = 'jwt_db_delete_old';
      final db = await open();
      await db.delete(from: jwts).where(jwts.id.equals(oldJwt.jwtId));
      logger.trace('done');

      return result;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Signs in a user if the credentials are valid
  ///
  /// Signs up a user if the record does not exist
  Future<_AuthResult?> _authenticate(
    String table,
    AuthPayload payload, {
    bool isAdmin = false,
  }) async {
    switch (payload) {
      case PasswordAuthPayload():
        return await _authenticatePassword(table, payload, isAdmin: isAdmin);

      case SendOtpAuthPayload():
        await _sendOtp(table, payload, isAdmin: isAdmin);
        return null;

      case SendMagicLinkAuthPayload():
        await _sendMagicLink(table, payload, isAdmin: isAdmin);
        return null;

      case ResetPasswordAuthPayload():
        await _sendResetPassword(table, payload, isAdmin: isAdmin);
        return null;

      case VerifyOtpAuthPayload():
      case VerifyMagicLinkAuthPayload():
      case ConfirmResetPasswordAuthPayload():
      case VerifyEmailAuthPayload():
        throw ArgumentError(
          'Call confirmAuth instead of authenticate to confirm a reset password',
        );
    }
  }

  Future<_AuthResult?> _authenticateAdmin(AuthPayload payload) async {
    final table = await _adminCollectionFor(payload.authType);

    return await _authenticate(table, payload, isAdmin: true);
  }

  Future<String> _adminCollectionFor(AuthType authType) async {
    final authTables = await _operations.send<AdminTablesResponse>(
      GetAdminTablesOperationRequest(),
    );

    StateError? lastError;
    for (final (table, authTypes) in authTables.tables) {
      if (!authTypes.contains(authType)) {
        continue;
      }

      try {
        return table;
      } on StateError catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        StateError('No $authType sign-in is configured for admin');
  }

  Future<_AuthResult> _signIntoCollection({
    required String table,
    required String email,
    required String? jwt,
    required AuthExtensionStep extensionStep,
  }) async {
    if (jwt != null) {
      throw const AlreadyAuthenticatedException();
    }

    final user = await _authRecord(table: table, email: email);
    logger.trace('auth_record_lookup', extra: {'found': user != null});
    if (user == null) {
      throw UserNotFoundAuthException(table: table);
    }

    final (newJwt, token) = await _createJwt(table, user);
    logger.trace('jwt_create');

    await _extensions.send<NoActionExtensionResponse>(switch (extensionStep) {
      .onSignIn => AuthExtensionRequest.onSignIn(
        table: table,
        object: user,
        jwt: newJwt,
      ),
      .onRefresh => AuthExtensionRequest.onRefresh(
        table: table,
        object: user,
        jwt: newJwt,
      ),
      _ => throw ArgumentError(
        'Unsupported auth extension step: $extensionStep',
      ),
    });
    logger.trace('ext_hook');

    await _executeEffects();
    logger.trace('done');

    return (user: user, jwt: token);
  }

  Future<List<AuthType>> _adminSupportedAuthTypes() async {
    final authTables = await _operations.send<AdminTablesResponse>(
      GetAdminTablesOperationRequest(),
    );

    final types = <AuthType>{};
    for (final (_, authTypes) in authTables.tables) {
      types.addAll(authTypes);
    }

    final sorted = types.toList()..sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  Future<(Jwt, String)> _createJwt(
    String table,
    Map<String, Object?> user,
  ) async {
    final jwtId = JwtId.generate();
    final userIdColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );

    final userId = switch (user[userIdColumn.name]) {
      final String userId => userId,
      _ => throw UserNotFoundAuthException(table: table),
    };

    final appConfig = await getConfig();

    final preJwt = Jwt.create(
      userId: userId,
      table: table,
      user: user,
      jwtId: jwtId,
      expiresIn: appConfig.jwtExpiresIn,
      claims: {},
    );

    final jwtConfig = await _operations.send<JwtConfigResponse>(
      GetJwtConfigOperationRequest(table: table, jwt: preJwt),
    );

    final config = jwtConfig.config;
    final expiresIn = config.expiresIn ?? appConfig.jwtExpiresIn;

    final jwt = Jwt(
      userId: preJwt.userId,
      table: preJwt.table,
      jwtId: preJwt.jwtId,
      expiresAt: clock.now().add(expiresIn),
      user: preJwt.user,
      claims: config.claims.toJson(),
      admin: (isAdmin: config.isAdmin, canEdit: config.canEdit),
    );

    final token = await _jwt.generate(jwt);

    final db = await open();

    await db.insert(into: jwts).values([
      JwtEntry(id: jwt.jwtId, userId: jwt.userId, expiresAt: jwt.expiresAt),
    ]);

    return (jwt, token);
  }
}
