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

    final resetPassword =
        (await _dispatchOperation<ResetPasswordConfigResponse>(
          GetResetPasswordConfigOperationRequest(table: table),
        )).config;

    final secret = switch (_insecureTestMode()) {
      true => kInsecureTestResetPasswordSecret,
      false => _randomChallengeSecret(),
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

    await _runExtension(
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

    final passwordColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: challenge.table, columnName: .password),
    );
    final idColumn = await _dispatchOperation<ColumnNameResponse>(
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

    // Not `hash(newPassword) == passwordHash`, which is what this was and
    // could never be true: [HashPassword.hash] mints a fresh random salt per
    // call and stores `<salt>.<digest>`, so two hashes of the *same* password
    // differ. The check was dead and reuse went through silently. `verify`
    // re-derives the digest from the stored salt, which is the only comparison
    // that answers the question.
    final reusesCurrentPassword = await _hashPassword.verify(
      rawPassword: payload.newPassword,
      passwordHash: passwordHash,
    );
    if (reusesCurrentPassword) {
      throw const PasswordReuseException();
    }

    final passwordColumnName = passwordColumn.name;
    final idColumnName = idColumn.name;
    if (passwordColumnName == null || idColumnName == null) {
      throw StateError('Missing column(s) for password reset');
    }

    // Consumed here rather than immediately after the secret check, which is
    // where it used to sit. That order was harmless only while the reuse check
    // could not fire; now that it can, spending the challenge first would burn
    // the link on a typo -- someone entering the password they already have
    // would be told to go request a whole new email. Everything that can still
    // reject this submission has run by now.
    await _consumeChallenge(challenge);

    final newPasswordHash = await _hashPassword.hash(
      password: payload.newPassword,
    );

    final operation = await _dispatchOperation<PerformOperationResponse>(
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

    // A reset is the remedy for a password someone else may know, so the
    // sessions that password minted must not outlive it -- otherwise an
    // attacker's JWT keeps working, for its whole expiry, against an account
    // whose owner believes they have just locked them out. Same revocation as
    // "log out everywhere" ([_logoutAll]) and admin removal.
    final revoked = await _revokeAllSessions(UnknownId(authRecordId));
    logger.verbose(
      'Reset password for $authRecordId, revoked $revoked session(s)',
      prefix: _prefix,
    );

    // The requirement is satisfied by the password CHANGING, not by the door
    // it changed through. Clearing here rather than in the forced-sign-in
    // path means an emailed reset also lifts a forced requirement -- which is
    // right: the demand was "choose a new password", never "choose it this
    // particular way". Doing it after the update and the revocation means a
    // submission that failed any earlier check leaves the requirement
    // standing.
    final db = await open();
    await db
        .delete(from: passwordResetRequirements)
        .where(
          passwordResetRequirements.table.equals(challenge.table) &
              passwordResetRequirements.userId.equals(UnknownId(authRecordId)),
        );
  }
}
