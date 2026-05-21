part of zonai_db;

extension _ResetPasswordX on ZonaiDb {
  Future<void> _sendResetPassword(
    String collection,
    ResetPasswordAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: payload,
    );

    if (!hasAuthRecord) {
      // silently fail (does not expose if the email exists or not)
      return;
    }

    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, .passwordReset, payload);

    final challenge = await _lastChallenge(
      collection: collection,
      email: payload.email,
      type: .passwordReset,
    );

    if (challenge != null) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw StateError(
          'Must wait 1 minute before sending a new reset password link',
        );
      }
    }

    await _expireOldChallenges(
      collection: collection,
      email: payload.email,
      type: .passwordReset,
    );

    final expiresIn = const Duration(minutes: 10);
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
        expiresAt: clock.now().add(expiresIn),
        secretHash: hashedSecret,
        target: payload.email,
        collection: collection,
      ),
    ]);

    final url = await _operations.send<ResetPasswordBaseUrlResponse>(
      GetResetPasswordBaseUrlOperationRequest(collection: collection),
    );

    courier.send(
      SendResetPasswordEmail(
        to: EmailAddress(address: payload.email),
        collection: collection,
        passwordResetUrl: '${url.url}?s=${Uri.encodeComponent(encodedToken)}',
        expiresIn: expiresIn,
      ),
    );
  }

  Future<void> _confirmResetPassword(
    ConfirmResetPasswordAuthPayload payload,
  ) async {
    final decodedToken = base64Decode(payload.token);
    final [secret, email] = utf8.decode(decodedToken).split(':');

    final challenge = await _lastChallenge(
      collection: null,
      email: email,
      type: .passwordReset,
    );

    if (challenge == null) {
      throw StateError('Invalid or expired reset password link');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw StateError('Reset password link expired');
    }

    final authRecord = await _authRecord(
      collection: challenge.collection,
      email: email,
      sanitize: false,
    );

    if (authRecord == null) {
      throw StateError('Invalid or expired reset password link');
    }

    await _requireAuthCollectionAccess(challenge.collection, payload);
    await _requireAuthRecordAccess(
      challenge.collection,
      .passwordReset,
      payload,
    );

    final secretMatches = await _hashPassword.verify(
      rawPassword: secret,
      passwordHash: challenge.secretHash,
    );
    if (!secretMatches) {
      throw StateError('Invalid or expired reset password link');
    }

    await _consumeChallenge(challenge);

    final passwordColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(
        collection: challenge.collection,
        columnName: .password,
      ),
    );
    final idColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: challenge.collection, columnName: .id),
    );

    final authRecordId = authRecord[idColumn.name];
    if (authRecordId is! String) {
      throw StateError('Auth record id not found');
    }

    final passwordHash = authRecord.remove(passwordColumn.name);
    if (passwordHash is! String) {
      throw StateError('Password hash not found');
    }

    final newPasswordHash = await _hashPassword.hash(
      password: payload.newPassword,
    );
    if (newPasswordHash == passwordHash) {
      throw StateError('New password cannot be the same as the old password');
    }

    final operation = await _operations.send<PerformOperationResponse>(
      UpdateOperationRequest(
        collection: challenge.collection,
        jwt: null,
        where: Eq(idColumn.name, authRecordId),
        updates: [ColumnUpdate(passwordColumn.name, Literal(newPasswordHash))],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null) {
      throw StateError('Failed to update auth record: $error');
    }

    if (result == null) {
      throw StateError('Failed to update auth record');
    }
  }
}
