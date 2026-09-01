part of zonai_db;

extension _PasswordX on ZonaiDb {
  Future<_AuthResult> _authenticatePassword(
    String table,
    PasswordAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    final hasAuthRecord = await _hasAuthRecord(table: table, payload: payload);

    if (hasAuthRecord) {
      return await _signInWithPassword(table, payload);
    }

    // A sign-in must never provision the account it was handed. This used to
    // fall straight through to [_signUpWithPassword] for every payload, so
    // `/auth/sign-in` (and `/auth` with `type: signIn`, and admin sign-in —
    // they all build a [SignInPasswordAuthPayload]) answered an unregistered
    // address differently from a registered one:
    //
    //  * on a table carrying a required column that only a sign-up body
    //    supplies — `name`, say — the insert cast null to String and the
    //    endpoint answered 500, while a wrong password on a real account
    //    answers 401. The status code alone told an unauthenticated caller
    //    whether an address had an account;
    //  * on a table with no such column it was worse than a leak: the
    //    account was created and a valid session handed back.
    //
    // Both close by failing exactly as a wrong password does. The message is
    // load-bearing too, not just the status: [UserNotFoundAuthException] also
    // maps to 401, but renders a different body, which is the same oracle
    // one layer down.
    if (payload is SignInPasswordAuthPayload) {
      throw const InvalidPasswordOrEmailException();
    }

    if (isAdmin) {
      throw UserNotFoundAuthException(table: table);
    }

    return await _signUpWithPassword(table, payload);
  }

  Future<_AuthResult> _signInWithPassword(
    String table,
    PasswordAuthPayload payload,
  ) async {
    logger.setTraceProps({'op': 'sign_in', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      if (payload.jwt != null) {
        throw const AlreadyAuthenticatedException();
      }

      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'row_access';
      await _requireAuthRecordAccess(table, .signIn, payload);
      logger.trace('row_access');

      step = 'password_verify';
      final user = await _passwordRecord(
        table: table,
        payload: payload,
        rawPassword: switch (payload) {
          PasswordAuthPayload() => payload.password,
        },
      );
      logger.trace('password_verify', extra: {'match': user != null});

      // Reached when the row exists but carries no usable password hash (an
      // OTP- or magic-link-only account, say). Same reasoning as above: a
      // distinct message here separates "this address exists but can't use a
      // password" from "wrong password", so both answer identically.
      if (user == null) {
        throw const InvalidPasswordOrEmailException();
      }

      step = 'reset_required';
      await _refuseIfPasswordResetRequired(table: table, user: user);
      logger.trace('reset_required');

      step = 'jwt_create';
      final (jwt, token) = await _createJwt(table, user);
      logger.trace('jwt_create');

      step = 'ext_hook';
      await _runExtension(
        AuthExtensionRequest.onSignIn(table: table, object: user, jwt: jwt),
      );
      logger.trace('ext_hook');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return (user: user, jwt: token);
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<_AuthResult> _signUpWithPassword(
    String table,
    PasswordAuthPayload payload,
  ) async {
    logger.setTraceProps({'op': 'sign_up', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'row_access';
      await _requireAuthRecordAccess(table, .signUp, payload);
      logger.trace('row_access');

      // Before the Argon2 hash, not after: declining costs the caller a
      // rules check and a hook call rather than a full KDF round, and the
      // hook has nothing to gain from a hash it must not see anyway.
      step = 'signup_gate';
      await _runSignUpGate(
        table,
        email: payload.email,
        object: payload.object,
        jwt: jwt,
      );
      logger.trace('signup_gate');

      // The write slot is reserved BEFORE the Argon2 hash, not after it, for
      // the same reason the sign-up gate runs before it: a sign-up the queue
      // is going to refuse should cost the checks above, not a full KDF
      // round. The slot is held through the hash and the INSERT and released
      // before the hooks and effects, which do not touch the writer.
      step = 'write_admit';
      final slot = await _admitWrite();
      final Object? error;
      final OperationResult? result;
      try {
        step = 'password_hash';
        final hashedPassword = await _hashPassword.hash(
          password: switch (payload) {
            PasswordAuthPayload() => payload.password,
          },
        );
        logger.trace('password_hash');

        step = 'sql_build';
        final operation = await _getOperation(
          CreateAuthOperationRequest(
            table: table,
            jwt: jwt,
            payload: PasswordAuthOperationPayload.save(
              email: payload.email,
              passwordHash: hashedPassword,
              object: payload.object,
            ),
          ),
        );
        logger.trace('sql_build');

        // Serialize the INSERT so concurrent signups don't hit SQLite busy /
        // write storms. Argon2 already finished above, off the writer lock.
        step = 'sql_execute';
        (error, result) = await _chainWrite(
          () => _execute((operation.query, operation.values)),
        );
        logger.trace('sql_execute');
      } finally {
        slot.release();
      }

      if (error != null || result == null) {
        throw error ?? AuthFailedException(cause: 'Failed to create user');
      }

      step = 'sanitize';
      final user = await _sanitizeRow(table, result.rows.single.toMap());
      logger.verbose('Created: ${user}', prefix: _prefix);
      logger.trace('sanitize');

      step = 'jwt_create';
      final (newJwt, token) = await _createJwt(table, user);
      logger.trace('jwt_create');

      step = 'ext_hook';
      await _runExtension(
        AuthExtensionRequest.onSignUp(table: table, object: user, jwt: newJwt),
      );
      logger.trace('ext_hook');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return (user: user, jwt: token);
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }
}
