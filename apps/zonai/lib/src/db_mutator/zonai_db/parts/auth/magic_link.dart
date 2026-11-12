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

    // An admin send never signs anyone up, so an address with no admin row
    // gets no link. It answers like a send that went out, as
    // `_sendResetPassword` does, so the reply says nothing about which
    // addresses are admins, and it keeps the same resend cooldown.
    if (isAdmin && !hasAuthRecord) {
      _holdSendWithoutAccount(
        table: table,
        email: payload.email,
        type: .magicLink,
      );
      return;
    }

    final operation = switch (hasAuthRecord) {
      true => AuthOperation.signIn,
      false => AuthOperation.signUp,
    };

    await _requireAuthTableAccess(table, payload);
    await _requireAuthRecordAccess(table, operation, payload);

    // Before the link is sent -- see the same block in `_sendOtp`. The
    // account is created at verify time, so gating only the insert let the
    // mail reach an address the app had already decided to refuse.
    //
    // The gate runs again at verify (`_signUpWithMagicLink`), so the hook is
    // AT LEAST ONCE for this flow.
    if (operation == AuthOperation.signUp) {
      await _runSignUpGate(
        table,
        email: payload.email,
        object: payload.object,
        jwt: await _extractJwt(payload),
      );
    }

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

    final challengeId = AuthChallengeId.generate();
    final encodedToken = _MagicLinkToken.encode(
      challengeId: challengeId,
      secret: secret,
      email: payload.email,
    );

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.magicLink(
        id: challengeId,
        expiresAt: clock.now().add(magicLink.expiresIn),
        metadata: payload.object,
        secretHash: hashedSecret,
        target: payload.email,
        table: table,
      ),
    ]);

    // What the sign-up gate queued (`mutate.*` from `beforeSignUp`) commits
    // here, after the challenge row, as a before-hook's writes commit after
    // the main write. Nothing later in this request drains the queue, so
    // without this they were dropped. Before the email: a write that fails
    // fails the request, and the code should not go out for it.
    await _executeEffects();

    final domain = switch (magicLink.path) {
      final path when path.startsWith('/') => '${appConfig.baseUrl}$path',
      final path when !path.startsWith('http') => '${appConfig.baseUrl}/$path',
      final path => path,
    };

    courier.sendInBackground(
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
    final token = _MagicLinkToken.decode(payload.secret);
    if (token == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'magic link');
    }
    final _MagicLinkToken(:secret, :email) = token;

    final challenge = await _magicLinkChallenge(token);

    if (challenge == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'magic link');
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

  /// The live challenge [token] opens, after checking its secret.
  ///
  /// A token that names its challenge is checked against that challenge
  /// only, so a link from an older email can never touch the newest one
  /// (#124). Once the secret matches, a replaced challenge says so, rather
  /// than "invalid or expired", because its holder's recovery is to open the
  /// newer email.
  ///
  /// A `secret:email` token (links sent before ids were added, and the ones
  /// insecure-test-mode clients build) is matched against the address's
  /// current challenge, as before.
  ///
  /// A wrong secret never spends an attempt. The secret is 256 random bits,
  /// so there is nothing to guess, and spending one is what let an older
  /// link lock out the newest.
  Future<AuthChallenge?> _magicLinkChallenge(_MagicLinkToken token) async {
    final AuthChallenge? challenge;
    if (token.challengeId case final id?) {
      final db = await open();
      final rows = await db
          .select()
          .from(authChallenges)
          .where(
            authChallenges.id.equals(id) &
                authChallenges.type.equals(AuthChallengeType.magicLink) &
                authChallenges.target.equals(token.email),
          )
          .limit(1);
      challenge = rows.singleOrNull;
    } else {
      challenge = await _lastChallenge(
        table: null,
        email: token.email,
        type: .magicLink,
      );
    }

    if (challenge == null) return null;

    final secretMatches = await _hashPassword.verify(
      rawPassword: token.secret,
      passwordHash: challenge.secretHash,
    );
    if (!secretMatches) return null;

    if (challenge.consumedAt != null) return null;

    if (!challenge.canConsume) {
      throw const MagicLinkReplacedException();
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'magic link');
    }

    if (challenge.allowedAttempts <= 0) return null;

    return challenge;
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

    await _runSignUpGate(table, email: email, object: object, jwt: appJwt);

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

    final result = await _insertAccountUnlessTaken(
      table: table,
      insert: operation,
      probe: MagicLinkAuthOperationPayload.get(email: email),
      jwt: appJwt,
    );
    if (result == null) {
      // Another sign-up for this address committed first (two verifies of
      // one code, say). Answer as the sign-in a later request would get.
      return await _signIntoCollection(
        table: table,
        email: email,
        jwt: jwt,
        extensionStep: .onSignIn,
      );
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

/// What a magic link's `s=` parameter carries: base64 of
/// `<challenge id>:<secret>:<email>`.
///
/// Links sent before #124 carry `<secret>:<email>`, with no id. Those still
/// decode, with a null [challengeId]. An id always ends in `_ach` and
/// neither a secret nor an id contains `:`, so the two cannot be confused.
class _MagicLinkToken {
  const _MagicLinkToken({
    required this.challengeId,
    required this.secret,
    required this.email,
  });

  final AuthChallengeId? challengeId;
  final String secret;
  final String email;

  static String encode({
    required AuthChallengeId challengeId,
    required String secret,
    required String email,
  }) => base64Encode(utf8.encode('${challengeId.value}:$secret:$email'));

  /// Null when [token] is not a magic-link token at all.
  static _MagicLinkToken? decode(String token) {
    final String decoded;
    try {
      decoded = utf8.decode(base64Decode(token));
    } on FormatException {
      return null;
    }

    final parts = decoded.split(':');
    if (parts.length < 2) return null;

    if (parts.length >= 3 && _idPattern.hasMatch(parts.first)) {
      return _MagicLinkToken(
        challengeId: AuthChallengeId(parts.first),
        secret: parts[1],
        email: parts.skip(2).join(':'),
      );
    }

    return _MagicLinkToken(
      challengeId: null,
      secret: parts.first,
      email: parts.skip(1).join(':'),
    );
  }

  static final _idPattern = RegExp(r'^[0-9a-f]{15}_ach$');
}
