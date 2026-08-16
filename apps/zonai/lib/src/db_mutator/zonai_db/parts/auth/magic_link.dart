part of zonai_db;

class _VerifyMagicLinkPayload implements VerifyMagicLinkAuthPayload {
  _VerifyMagicLinkPayload({
    required this.secret,
    required this.email,
    required this.jwt,
  }) : authType = .magicLink;

  final String secret;
  final String email;
  final String? jwt;
  final AuthType authType;
}

extension _MagicLinkX on ZonaiDb {
  Future<void> _sendMagicLink(
    String table,
    SendMagicLinkAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(table: table, payload: payload);

    if (isAdmin) {
      if (!hasAuthRecord) {
        throw UserNotFoundAuthException(table: table);
      }
    }

    final operation = switch (hasAuthRecord) {
      true => AuthOperation.signIn,
      false => AuthOperation.signUp,
    };

    await _requireAuthTableAccess(table, payload);
    await _requireAuthRecordAccess(table, operation, payload);
    final lastMagicLink = await _lastChallenge(
      table: table,
      email: payload.email,
      type: .magicLink,
    );

    if (lastMagicLink case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    await _expireOldChallenges(
      table: table,
      email: payload.email,
      type: .magicLink,
    );

    final magicLink = (await _dispatchOperation<MagicLinkConfigResponse>(
      GetMagicLinkConfigOperationRequest(table: table),
    )).config;

    final appConfig = await configResolver.resolve();

    final secret = switch (_insecureTestMode()) {
      true => kInsecureTestMagicLinkSecret,
      false => _randomChallengeSecret(),
    };
    final hashedSecret = await _hashPassword.hash(password: secret);

    final encodedToken = base64Encode('$secret:${payload.email}'.codeUnits);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.magicLink(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(magicLink.expiresIn),
        metadata: payload.object,
        secretHash: hashedSecret,
        target: payload.email,
        table: table,
      ),
    ]);

    final domain = switch (magicLink.path) {
      final path when path.startsWith('/') => '${appConfig.baseUrl}$path',
      final path when !path.startsWith('http') => '${appConfig.baseUrl}/$path',
      final path => path,
    };

    courier.send(
      SendMagicLinkEmail(
        to: EmailAddress(address: payload.email),
        table: table,
        isResend: lastMagicLink != null,
        magicLinkUrl: '$domain?s=${Uri.encodeComponent(encodedToken)}',
        expiresIn: magicLink.expiresIn,
        variables: payload.object,
      ),
    );
  }

  Future<_AuthResult> _verifyMagicLink(
    VerifyMagicLinkAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final decodedToken = base64Decode(payload.secret);
    final [secret, email] = utf8.decode(decodedToken).split(':');

    final challenge = await _lastChallenge(
      table: null,
      email: email,
      type: .magicLink,
    );

    if (challenge == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'magic link');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'magic link');
    }

    final hasAuthRecord = await _hasAuthRecord(
      table: challenge.table,
      payload: _VerifyMagicLinkPayload(
        secret: secret,
        email: email,
        jwt: payload.jwt,
      ),
    );

    if (isAdmin) {
      if (!hasAuthRecord) {
        throw UserNotFoundAuthException(table: challenge.table);
      }
    }

    final operation = switch (hasAuthRecord) {
      true => AuthOperation.signIn,
      false => AuthOperation.signUp,
    };

    await _requireAuthTableAccess(challenge.table, payload);
    await _requireAuthRecordAccess(challenge.table, operation, payload);

    final secretMatches = await _hashPassword.verify(
      rawPassword: secret,
      passwordHash: challenge.secretHash,
    );
    if (!secretMatches) {
      await _challengeFailed(challenge);
      throw const InvalidOrExpiredCodeException(codeType: 'magic link');
    }

    await _consumeChallenge(challenge);

    if (hasAuthRecord) {
      return await _signIntoCollection(
        table: challenge.table,
        email: email,
        jwt: payload.jwt,
        extensionStep: .onSignIn,
      );
    }

    return await _signUpWithMagicLink(
      challenge.table,
      email: email,
      object: challenge.metadata,
      jwt: payload.jwt,
    );
  }

  Future<_AuthResult> _signUpWithMagicLink(
    String table, {
    required String email,
    String? jwt,
    Map<String, Object?>? object,
  }) async {
    final appJwt = await _extractJwt(
      SendMagicLinkAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthTableAccess(
      table,
      SendMagicLinkAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthRecordAccess(
      table,
      .signUp,
      SendMagicLinkAuthPayload(email: email, object: object, jwt: jwt),
    );

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        table: table,
        jwt: appJwt,
        payload: MagicLinkAuthOperationPayload.save(
          email: email,
          object: {...?object},
        ),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));

    if (error != null || result == null) {
      throw error ?? AuthFailedException(cause: 'Failed to create user');
    }

    final user = await _sanitizeRow(table, result.rows.single.toMap());

    logger.verbose('Created user using OTP', prefix: _prefix);

    final (newJwt, token) = await _createJwt(table, user);

    await _runExtension(
      AuthExtensionRequest.onSignUp(table: table, object: user, jwt: newJwt),
    );

    await _executeEffects();

    return (user: user, jwt: token);
  }
}
