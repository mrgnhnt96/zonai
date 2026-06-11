part of zonai_db;

extension _ResetPasswordX on ZonaiDb {
  Future<void> _sendResetPassword(
    String table,
    ResetPasswordAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(table: table, payload: payload);

    if (!hasAuthRecord) {
      // silently fail (does not expose if the email exists or not)
      return;
    }

    await _requireAuthTableAccess(table, payload);
    await _requireAuthRecordAccess(table, .passwordReset, payload);

    final challenge = await _lastChallenge(
      table: table,
      email: payload.email,
      type: .passwordReset,
    );

    if (challenge != null) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    await _expireOldChallenges(
      table: table,
      email: payload.email,
      type: .passwordReset,
    );

    final resetPassword = (await _operations.send<ResetPasswordConfigResponse>(
      GetResetPasswordConfigOperationRequest(table: table),
    )).config;

    final secret = switch (kIsCompiled) {
      false => 'dev-reset-password',
      true => List.generate(
        32,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    };
    final hashedSecret = await _hashPassword.hash(password: secret);

    final encodedToken = base64Encode('$secret:${payload.email}'.codeUnits);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.passwordReset(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(resetPassword.expiresIn),
        secretHash: hashedSecret,
        target: payload.email,
        table: table,
      ),
    ]);

    final appConfig = await configResolver.resolve();
    final domain = switch (resetPassword.path) {
      final path when path.startsWith('/') => '${appConfig.baseUrl}$path',
      final path when !path.startsWith('http') => '${appConfig.baseUrl}/$path',
      final path => path,
    };

    courier.send(
      SendResetPasswordEmail(
        to: EmailAddress(address: payload.email),
        table: table,
        passwordResetUrl: '$domain?s=${Uri.encodeComponent(encodedToken)}',
        expiresIn: resetPassword.expiresIn,
      ),
    );

    final user = await _authRecord(table: table, email: payload.email);
    if (user == null) {
      return;
    }

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onPasswordReset(
        table: table,
        object: user,
        jwt: await _extractJwt(payload),
      ),
    );

    await _executeEffects();
  }

  Future<void> _confirmResetPassword(
    ConfirmResetPasswordAuthPayload payload,
  ) async {
    final decodedToken = base64Decode(payload.token);
    final [secret, email] = utf8.decode(decodedToken).split(':');

    final challenge = await _lastChallenge(
      table: null,
      email: email,
      type: .passwordReset,
    );

    if (challenge == null) {
      throw const InvalidOrExpiredResetPasswordLinkException();
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const ResetPasswordLinkExpiredException();
    }

    final authRecord = await _authRecord(
      table: challenge.table,
      email: email,
      sanitize: false,
    );

    if (authRecord == null) {
      throw const InvalidOrExpiredResetPasswordLinkException();
    }

    await _requireAuthTableAccess(challenge.table, payload);
    await _requireAuthRecordAccess(challenge.table, .passwordReset, payload);

    final secretMatches = await _hashPassword.verify(
      rawPassword: secret,
      passwordHash: challenge.secretHash,
    );
    if (!secretMatches) {
      throw const InvalidOrExpiredResetPasswordLinkException();
    }

    await _consumeChallenge(challenge);

    final passwordColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(table: challenge.table, columnName: .password),
    );
    final idColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(table: challenge.table, columnName: .id),
    );

    final authRecordId = authRecord[idColumn.name];
    if (authRecordId is! String) {
      throw AuthFailedException(cause: 'Auth record id not found');
    }

    final passwordHash = authRecord.remove(passwordColumn.name);
    if (passwordHash is! String) {
      throw AuthFailedException(cause: 'Password hash not found');
    }

    final newPasswordHash = await _hashPassword.hash(
      password: payload.newPassword,
    );
    if (newPasswordHash == passwordHash) {
      throw const PasswordReuseException();
    }

    final passwordColumnName = passwordColumn.name;
    final idColumnName = idColumn.name;
    if (passwordColumnName == null || idColumnName == null) {
      throw StateError('Missing column(s) for password reset');
    }

    final operation = await _operations.send<PerformOperationResponse>(
      UpdateOperationRequest(
        table: challenge.table,
        jwt: null,
        where: Eq(idColumnName, authRecordId),
        updates: [ColumnUpdate(passwordColumnName, Literal(newPasswordHash))],
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
