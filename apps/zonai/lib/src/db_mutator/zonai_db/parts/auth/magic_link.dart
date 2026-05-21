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
    String collection,
    SendMagicLinkAuthPayload payload, {
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
    final lastMagicLink = await _lastChallenge(
      collection: collection,
      email: payload.email,
      type: .magicLink,
    );

    if (lastMagicLink case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw StateError('Must wait 1 minute before sending a new OTP');
      }
    }

    await _expireOldChallenges(
      collection: collection,
      email: payload.email,
      type: .magicLink,
    );

    final expiresIn = const Duration(minutes: 10);
    final secret = switch (kIsCompiled) {
      false => 'dev-magic-link',
      true => List.generate(
        32,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    };
    final hashedSecret = await _hashPassword.hash(password: secret);

    final encodedToken = base64Encode('$secret:${payload.email}'.codeUnits);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.magicLink(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(expiresIn),
        metadata: payload.object,
        secretHash: hashedSecret,
        target: payload.email,
        collection: collection,
      ),
    ]);

    final url = await _operations.send<MagicLinkBaseUrlResponse>(
      GetMagicLinkBaseUrlOperationRequest(collection: collection),
    );

    courier.send(
      SendMagicLinkEmail(
        to: EmailAddress(address: payload.email),
        collection: collection,
        isResend: lastMagicLink != null,
        magicLinkUrl: '${url.url}?s=${Uri.encodeComponent(encodedToken)}',
        expiresIn: expiresIn,
        variables: payload.object,
      ),
    );
  }

  Future<_AuthResult> _verifyMagicLink(
    String collection,
    VerifyMagicLinkAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final decodedToken = base64Decode(payload.secret);
    final [secret, email] = utf8.decode(decodedToken).split(':');

    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: _VerifyMagicLinkPayload(
        secret: secret,
        email: email,
        jwt: payload.jwt,
      ),
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

    final challenge = await _lastChallenge(
      collection: collection,
      email: email,
      type: .magicLink,
    );

    if (challenge == null) {
      throw StateError('Invalid or expired code');
    }

    if (challenge.type != .magicLink) {
      throw StateError('Invalid or expired magic link');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw StateError('Code expired');
    }

    final secretHash = challenge.secretHash;
    if (secretHash == null) {
      throw StateError('Invalid or expired code');
    }

    final secretMatches = await _hashPassword.verify(
      rawPassword: secret,
      passwordHash: secretHash,
    );
    if (!secretMatches) {
      throw StateError('Invalid or expired magic link');
    }

    await _consumeChallenge(challenge);

    if (hasAuthRecord) {
      return await _signIntoCollection(
        collection: collection,
        email: email,
        jwt: payload.jwt,
      );
    }

    return await _signUpWithMagicLink(
      collection,
      email: email,
      object: challenge.metadata,
      jwt: payload.jwt,
    );
  }

  Future<_AuthResult> _signUpWithMagicLink(
    String collection, {
    required String email,
    String? jwt,
    Map<String, Object?>? object,
  }) async {
    final appJwt = await _extractJwt(
      SendMagicLinkAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthCollectionAccess(
      collection,
      SendMagicLinkAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthRecordAccess(
      collection,
      .signUp,
      SendMagicLinkAuthPayload(email: email, object: object, jwt: jwt),
    );

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        collection: collection,
        jwt: appJwt,
        payload: MagicLinkAuthOperationPayload.save(
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
