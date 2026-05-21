part of zonai_db;

extension _OtpX on ZonaiDb {
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

    final lastOtp = await _lastChallenge(
      collection: collection,
      email: payload.email,
    );

    if (lastOtp case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw StateError('Must wait 1 minute before sending a new OTP');
      }
    }

    await _expireOldChallenges(
      collection: collection,
      email: payload.email,
      type: .otp,
    );

    final expiresIn = const Duration(minutes: 10);
    final otp = switch (kIsCompiled) {
      false => '123456',
      true => Random.secure().nextInt(1000000).toString().padLeft(6, '0'),
    };
    final hashedOtp = await _hashPassword.hash(password: otp);

    final db = await open();
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
        isResend: lastOtp != null,
        code: otp,
        expiresIn: expiresIn,
        variables: payload.object,
      ),
    );
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

    final challenge = await _lastChallenge(
      collection: collection,
      email: payload.email,
    );

    if (challenge == null) {
      throw StateError('Invalid or expired code');
    }

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

    await _consumeChallenge(challenge);

    if (hasAuthRecord) {
      return await _signIntoCollection(
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
}
