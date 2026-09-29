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

      // Only a session zonai issued can be extended. `_extractJwt` also
      // honours external-IdP tokens, which have no `_jwt` row -- their expiry
      // and revocation live with the IdP -- and exchanging one here would turn
      // a short-lived, IdP-revocable token into a zonai session refreshable
      // indefinitely. The row must also belong to the token's user.
      step = 'session_lookup';
      final db = await open();
      final sessions = await db
          .select()
          .from(jwts)
          .where(jwts.id.equals(oldJwt.jwtId));
      final issuedHere = sessions.any(
        (session) => session.userId.value == oldJwt.userId.value,
      );
      logger.trace('session_lookup', extra: {'found': issuedHere});
      if (!issuedHere) {
        throw const JwtRecordNotFoundException();
      }

      // By id, never by the email in the token's `user` snapshot. An address
      // can change after the token is issued and then belong to someone else;
      // resolving by it refreshed one user's token into another user's
      // account. The id is what the session belongs to.
      step = 'user_lookup';
      final user = await _authRecordById(
        table: oldJwt.table,
        userId: oldJwt.userId.value,
      );
      logger.trace('user_lookup', extra: {'found': user != null});
      if (user == null) {
        throw UserNotFoundAuthException(table: oldJwt.table);
      }

      step = 'sign_in';
      final result = await _issueSession(
        table: oldJwt.table,
        user: user,
        extensionStep: .onRefresh,
      );
      logger.trace('sign_in');

      step = 'jwt_db_delete_old';
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

      case final NativeOAuthAuthPayload payload:
        return await _nativeOAuth(table, payload, isAdmin: isAdmin);

      case StartOAuthAuthPayload():
        throw ArgumentError(
          'Call startOAuth instead of authenticate to begin an OAuth flow',
        );

      case CompleteOAuthAuthPayload():
        throw ArgumentError(
          'Call completeOAuth instead of authenticate to complete an OAuth flow',
        );

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
    final authTables = await _dispatchOperation<AdminTablesResponse>(
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

    return await _issueSession(
      table: table,
      user: user,
      extensionStep: extensionStep,
    );
  }

  /// Mints a session for an already-resolved, sanitized [user] row and runs
  /// the sign-in or refresh hook for it.
  Future<_AuthResult> _issueSession({
    required String table,
    required Map<String, Object?> user,
    required AuthExtensionStep extensionStep,
  }) async {
    final (newJwt, token) = await _createJwt(table, user);
    logger.trace('jwt_create');

    await _runExtension(switch (extensionStep) {
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

  /// The configured `AsAdmin` table and the auth types it supports,
  /// resolved once regardless of sign-in method -- `admin add` and its
  /// siblings need to know what an admin table actually supports before
  /// assuming it takes a password (design: oauth-admin-add).
  Future<(String table, List<AuthType> authTypes)> _adminTable() async {
    final authTables = await _dispatchOperation<AdminTablesResponse>(
      GetAdminTablesOperationRequest(),
    );

    if (authTables.tables.isEmpty) {
      throw StateError(
        'No admin table is configured (mix AsAdmin into an auth table)',
      );
    }

    return authTables.tables.first;
  }

  /// The auth types a *named* `AsAdmin` table declares.
  ///
  /// [_adminTable] answers for the first configured one and
  /// [_adminSupportedAuthTypes] answers for the union across all of them;
  /// neither is right for a caller that already knows which table it is
  /// acting on, such as an invite being accepted in the table it was issued
  /// for.
  ///
  /// Throws when [table] is not an admin table at all, rather than returning
  /// an empty list -- an empty list reads as "supports nothing", which a
  /// caller checking `contains(AuthType.password)` would silently treat as a
  /// passwordless table.
  Future<List<AuthType>> _adminTableAuthTypes(String table) async {
    final authTables = await _dispatchOperation<AdminTablesResponse>(
      GetAdminTablesOperationRequest(),
    );

    for (final (tableName, authTypes) in authTables.tables) {
      if (tableName == table) return authTypes;
    }

    throw StateError('"$table" is not a configured admin table');
  }

  Future<List<AuthType>> _adminSupportedAuthTypes() async {
    final authTables = await _dispatchOperation<AdminTablesResponse>(
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
    final userIdColumn = await _dispatchOperation<ColumnNameResponse>(
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

    final jwtConfig = await _dispatchOperation<JwtConfigResponse>(
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
      isAnonymous: await _isAnonymousRow(table, user),
    );

    final token = await _jwt.generate(jwt);

    final db = await open();

    // `anonymous` is recorded with the session, not only in the token, so
    // `_validateJwt` re-derives it from here on every request.
    await db.insert(into: jwts).values([
      JwtEntry(
        id: jwt.jwtId,
        userId: jwt.userId,
        expiresAt: jwt.expiresAt,
        anonymous: jwt.isAnonymous,
      ),
    ]);

    return (jwt, token);
  }
}
