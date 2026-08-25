part of zonai_db;

extension _OtpX on ZonaiDb {
  Future<void> _sendOtp(
    String table,
    SendOtpAuthPayload payload, {
    bool isAdmin = false,
    Jwt? callerJwt,
  }) async {
    final jwt = callerJwt ?? await _extractJwt(payload);
    await _requireAdminOrOwnEmail(
      table: table,
      email: payload.email,
      jwt: jwt,
      allowUnauthenticated: true,
    );

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

    // Before the code is sent, not after it is verified. The account is
    // created at verify time, so wiring the gate to the INSERT -- correct for
    // the password flow, where the insert is in this same request -- left the
    // app's refusal landing ten minutes late, to a caller who was never going
    // to verify. The email had already gone out to an address the app had
    // said it did not want.
    //
    // Everything the candidate needs is in hand here: `operation` above
    // already decided this is a sign-up, and `payload.object` is trusted
    // enough at this point to be persisted onto the challenge and
    // interpolated into the mail below.
    //
    // The gate also runs again at verify (`_signUpWithOtp`), which is the
    // last point before the row exists and a challenge is valid for ten
    // minutes. So the hook is AT LEAST ONCE for this flow, and its body has
    // to tolerate that.
    if (operation == AuthOperation.signUp) {
      await _runSignUpGate(
        table,
        email: payload.email,
        object: payload.object,
        jwt: jwt,
      );
    }

    final lastOtp = await _lastChallenge(
      table: table,
      email: payload.email,
      type: .otp,
    );

    if (lastOtp case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    await _expireOldChallenges(table: table, email: payload.email, type: .otp);

    final expiresIn = const Duration(minutes: 10);
    final otp = switch (_insecureTestMode()) {
      true => kInsecureTestOtp,
      false => Random.secure().nextInt(1000000).toString().padLeft(6, '0'),
    };
    final hashedOtp = await _hashPassword.hash(password: otp);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.otp(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(expiresIn),
        metadata: payload.object,
        secretHash: hashedOtp,
        target: payload.email,
        table: table,
      ),
    ]);

    courier.send(
      SendOtpEmail(
        to: EmailAddress(address: payload.email),
        table: table,
        isResend: lastOtp != null,
        code: otp,
        expiresIn: expiresIn,
        variables: payload.object,
      ),
    );
  }

  Future<_AuthResult> _verifyOtp(
    VerifyOtpAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final challenge = await _lastChallenge(
      table: null,
      email: payload.email,
      type: .otp,
    );

    if (challenge == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'OTP');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'OTP');
    }

    final hasAuthRecord = await _hasAuthRecord(
      table: challenge.table,
      payload: payload,
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

    final codeMatches = await _hashPassword.verify(
      rawPassword: payload.code,
      passwordHash: challenge.secretHash,
    );
    if (!codeMatches) {
      await _challengeFailed(challenge);
      throw const InvalidOrExpiredCodeException(codeType: 'OTP');
    }

    await _consumeChallenge(challenge);

    if (hasAuthRecord) {
      return await _signIntoCollection(
        table: challenge.table,
        email: payload.email,
        jwt: payload.jwt,
        extensionStep: .onSignIn,
      );
    }

    return await _signUpWithOtp(
      challenge.table,
      email: payload.email,
      object: challenge.metadata,
      jwt: payload.jwt,
    );
  }

  Future<_AuthResult> _signUpWithOtp(
    String table, {
    required String email,
    Map<String, Object?>? object,
    String? jwt,
  }) async {
    final appJwt = await _extractJwt(
      SendOtpAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthTableAccess(
      table,
      SendOtpAuthPayload(email: email, jwt: jwt),
    );
    await _requireAuthRecordAccess(
      table,
      .signUp,
      SendOtpAuthPayload(email: email, object: object, jwt: jwt),
    );

    await _runSignUpGate(table, email: email, object: object, jwt: appJwt);

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        table: table,
        jwt: appJwt,
        payload: OtpAuthOperationPayload.save(
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
