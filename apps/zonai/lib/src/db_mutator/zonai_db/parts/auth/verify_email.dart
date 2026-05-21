part of zonai_db;

extension _VerifyEmailX on ZonaiDb {
  Future<void> _sendVerifyEmail(
    String collection, {
    required String email,
    Map<String, dynamic>? variables,
    Jwt? jwt,
  }) async {
    await _requireAdminOrOwnEmail(
      collection: collection,
      email: email,
      jwt: jwt,
      allowUnauthenticated: false,
    );

    final authRecord = await _authRecord(collection: collection, email: email);
    if (authRecord == null) {
      return;
    }

    final isVerifiedColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: collection, columnName: .isVerified),
    );

    if (authRecord[isVerifiedColumn.name] == true) {
      return;
    }

    final lastChallenge = await _lastChallenge(
      collection: collection,
      email: email,
      type: .verifyEmail,
    );

    if (lastChallenge case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw StateError(
          'Must wait 1 minute before sending a new verify email',
        );
      }
    }

    await _expireOldChallenges(
      collection: collection,
      email: email,
      type: .verifyEmail,
    );

    final verifyEmail = (await _operations.send<VerifyEmailConfigResponse>(
      GetVerifyEmailConfigOperationRequest(collection: collection),
    )).config;

    final secret = switch (kIsCompiled) {
      false => 'dev-verify-email',
      true => List.generate(
        32,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    };
    final hashedSecret = await _hashPassword.hash(password: secret);

    final encodedToken = base64Encode('$secret:$email'.codeUnits);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.verifyEmail(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(verifyEmail.expiresIn),
        metadata: variables,
        secretHash: hashedSecret,
        target: email,
        collection: collection,
      ),
    ]);

    final appConfig = await configResolver.resolve();
    final domain = switch (verifyEmail.path) {
      final path when path.startsWith('/') => '${appConfig.baseUrl}$path',
      final path when !path.startsWith('http') => '${appConfig.baseUrl}/$path',
      final path => path,
    };

    courier.send(
      SendVerifyEmailEmail(
        to: EmailAddress(address: email),
        collection: collection,
        verificationUrl: '$domain?s=${Uri.encodeComponent(encodedToken)}',
        expiresIn: verifyEmail.expiresIn,
        variables: variables,
      ),
    );
  }

  Future<void> _verifyEmail(VerifyEmailAuthPayload payload) async {
    final decodedToken = base64Decode(payload.token);
    final [secret, email] = utf8.decode(decodedToken).split(':');

    final challenge = await _lastChallenge(
      collection: null,
      email: email,
      type: .verifyEmail,
    );

    if (challenge == null) {
      throw StateError('Invalid or expired verify email link');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw StateError('Verify email link expired');
    }

    final authRecord = await _authRecord(
      collection: challenge.collection,
      email: email,
      sanitize: false,
    );

    if (authRecord == null) {
      throw StateError('Invalid or expired verify email link');
    }

    final secretMatches = await _hashPassword.verify(
      rawPassword: secret,
      passwordHash: challenge.secretHash,
    );
    if (!secretMatches) {
      throw StateError('Invalid or expired verify email link');
    }

    await _consumeChallenge(challenge);

    final isVerifiedColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(
        collection: challenge.collection,
        columnName: .isVerified,
      ),
    );
    final idColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: challenge.collection, columnName: .id),
    );

    final authRecordId = authRecord[idColumn.name];
    if (authRecordId is! String) {
      throw StateError('Auth record id not found');
    }

    if (authRecord[isVerifiedColumn.name] == true) {
      return;
    }

    final jwt = await _extractJwt(payload);

    final operation = await _operations.send<PerformOperationResponse>(
      UpdateOperationRequest(
        collection: challenge.collection,
        jwt: jwt,
        where: Eq(idColumn.name, authRecordId),
        updates: [ColumnUpdate(isVerifiedColumn.name, Literal(true))],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null) {
      throw StateError('Failed to verify email: $error');
    }

    if (result == null) {
      throw StateError('Failed to verify email');
    }
  }
}
