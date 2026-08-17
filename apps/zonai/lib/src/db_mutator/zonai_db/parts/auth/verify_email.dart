part of zonai_db;

extension _VerifyEmailX on ZonaiDb {
  Future<void> _sendVerifyEmail(
    String table, {
    required String email,
    Map<String, dynamic>? variables,
    Jwt? jwt,
  }) async {
    await _requireAdminOrOwnEmail(
      table: table,
      email: email,
      jwt: jwt,
      allowUnauthenticated: false,
    );

    final authRecord = await _authRecord(table: table, email: email);
    if (authRecord == null) {
      return;
    }

    final isVerifiedColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .isVerified),
    );

    if (authRecord[isVerifiedColumn.name] == true) {
      return;
    }

    final lastChallenge = await _lastChallenge(
      table: table,
      email: email,
      type: .verifyEmail,
    );

    if (lastChallenge case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    await _expireOldChallenges(table: table, email: email, type: .verifyEmail);

    final verifyEmail = (await _dispatchOperation<VerifyEmailConfigResponse>(
      GetVerifyEmailConfigOperationRequest(table: table),
    )).config;

    final secret = switch (_insecureTestMode()) {
      true => kInsecureTestVerifyEmailSecret,
      false => _randomChallengeSecret(),
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
        table: table,
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
        table: table,
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
      table: null,
      email: email,
      type: .verifyEmail,
    );

    if (challenge == null) {
      throw const InvalidOrExpiredVerifyEmailLinkException();
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const VerifyEmailLinkExpiredException();
    }

    final authRecord = await _authRecord(
      table: challenge.table,
      email: email,
      sanitize: false,
    );

    if (authRecord == null) {
      throw const InvalidOrExpiredVerifyEmailLinkException();
    }

    final secretMatches = await _hashPassword.verify(
      rawPassword: secret,
      passwordHash: challenge.secretHash,
    );
    if (!secretMatches) {
      throw const InvalidOrExpiredVerifyEmailLinkException();
    }

    await _consumeChallenge(challenge);

    final isVerifiedColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: challenge.table, columnName: .isVerified),
    );
    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: challenge.table, columnName: .id),
    );

    final authRecordId = authRecord[idColumn.name];
    if (authRecordId is! String) {
      throw AuthFailedException(cause: 'Auth record id not found');
    }

    if (authRecord[isVerifiedColumn.name] == true) {
      return;
    }

    final jwt = await _extractJwt(payload);

    final isVerifiedColumnName = isVerifiedColumn.name;
    final idColumnName = idColumn.name;
    if (isVerifiedColumnName == null || idColumnName == null) {
      throw StateError('Missing column(s) for email verification');
    }

    final operation = await _dispatchOperation<PerformOperationResponse>(
      UpdateOperationRequest(
        table: challenge.table,
        jwt: jwt,
        where: Eq(idColumnName, authRecordId),
        updates: [ColumnUpdate(isVerifiedColumnName, Literal(true))],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null) {
      throw AuthFailedException(cause: error);
    }

    if (result == null) {
      throw const AuthFailedException();
    }
  }
}
