part of zonai_db;

extension _PasswordResetRequirementX on ZonaiDb {
  /// Marks [email]'s account in [table] as owing a new password, and kills
  /// every session it currently holds.
  ///
  /// Design: `docs/force-password-reset-design.md` §4.1.
  Future<void> _requirePasswordReset({
    required String table,
    required String email,
    required PasswordResetReason reason,
    String? byUserId,
  }) async {
    // Not sanitized: the id column is read below, and sanitizing can drop it.
    final user = await _authRecord(table: table, email: email, sanitize: false);
    if (user == null) {
      // Named, unlike the auth flows. Those answer an unknown address exactly
      // as they answer a wrong password, because an unauthenticated caller
      // must not learn which addresses exist. This is reached only by an
      // already-authenticated admin or by the CLI on the server box, so there
      // is no oracle to protect and a silent success would be a worse
      // outcome -- an operator would believe a compromised account had been
      // locked down when nothing had happened. Same posture as
      // [_resetAdminPassword].
      throw StateError('No account with email "$email" exists in "$table"');
    }

    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );
    final passwordColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .password),
    );

    final idColumnName = idColumn.name;
    if (idColumnName == null) {
      throw StateError('Missing id column for "$table"');
    }

    // A collection with no password column cannot authenticate with one, so
    // the gate in [_signInWithPassword] would never read this row. Refusing
    // loudly beats writing a requirement that is unenforceable by
    // construction: an operator who "forced a reset" on an OAuth-only table
    // and got a success would reasonably believe the account was constrained.
    if (passwordColumn.name == null) {
      throw StateError(
        '"$table" has no password column, so a password reset cannot be '
        'required of it -- the sign-in path this would gate does not exist',
      );
    }

    final userId = user[idColumnName];
    if (userId is! String) {
      throw StateError('Auth record id not found in "$table"');
    }

    final db = await open();

    // Delete-then-insert rather than one `INSERT OR REPLACE`: the unique index
    // on (table, user_id) makes a second plain insert fail, and the builder
    // this codebase uses does not surface a conflict clause. Two statements
    // for a write an operator performs by hand is not a cost worth optimising,
    // and the pair reads as what it is -- setting the requirement again
    // replaces it rather than stacking a duplicate that a later clear would
    // only half-remove.
    await db
        .delete(from: passwordResetRequirements)
        .where(
          passwordResetRequirements.table.equals(table) &
              passwordResetRequirements.userId.equals(UnknownId(userId)),
        );

    await db.insert(into: passwordResetRequirements).values([
      PasswordResetRequirement(
        id: PasswordResetRequirementId.generate(),
        table: table,
        userId: UnknownId(userId),
        reason: reason,
        createdBy: byUserId,
      ),
    ]);

    // LOAD-BEARING, and the reason this is not merely tidy: without it the
    // control binds only sign-ins that have not happened yet. Anyone already
    // holding a session -- including whoever the password leaked to -- keeps
    // it for the rest of `jwtExpiresIn` (14 days by default) while the
    // account's owner believes they have just locked them out. Same call
    // [_confirmResetPassword] makes after a reset, and [_logoutAll], and
    // admin removal.
    final revoked = await _revokeAllSessions(UnknownId(userId));

    logger.verbose(
      'Required a password reset for $userId in "$table" '
      '(${reason.name}), revoked $revoked session(s)',
      prefix: _prefix,
    );
  }

  /// Lifts the requirement without the account having satisfied it.
  ///
  /// The operator escape hatch (design §4.2): a requirement set on the wrong
  /// address has to be removable, or a typo locks someone out of an account
  /// they still own. Returns whether a row was actually removed, so a caller
  /// can tell "cleared" from "there was nothing to clear".
  Future<bool> _clearPasswordResetRequirement({
    required String table,
    required String email,
  }) async {
    final user = await _authRecord(table: table, email: email, sanitize: false);
    if (user == null) {
      throw StateError('No account with email "$email" exists in "$table"');
    }

    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );

    final idColumnName = idColumn.name;
    if (idColumnName == null) {
      throw StateError('Missing id column for "$table"');
    }

    final userId = user[idColumnName];
    if (userId is! String) {
      throw StateError('Auth record id not found in "$table"');
    }

    final db = await open();
    final removed = await db
        .delete(from: passwordResetRequirements)
        .where(
          passwordResetRequirements.table.equals(table) &
              passwordResetRequirements.userId.equals(UnknownId(userId)),
        )
        .returning();

    if (removed.isNotEmpty) {
      logger.verbose(
        'Cleared the password reset requirement for $userId in "$table"',
        prefix: _prefix,
      );
    }

    return removed.isNotEmpty;
  }

  /// The requirement standing against [email]'s account in [table], or null.
  ///
  /// The by-email twin of [_passwordResetRequirement], which is keyed on the
  /// account id. Both exist because the two callers hold different things: the
  /// sign-in gate has already resolved the row and would waste a lookup, while
  /// an operator surface -- the dashboard's row panel -- has only an address.
  ///
  /// Throws on an unknown address, matching [_requirePasswordReset] and
  /// [_clearPasswordResetRequirement] rather than the auth flows: every caller
  /// here is an authenticated admin or the CLI on the server box, so there is
  /// no enumeration oracle to protect, and a silent null would read as "this
  /// account owes nothing" for an address that does not exist.
  Future<PasswordResetRequirement?> _passwordResetRequirementForEmail({
    required String table,
    required String email,
  }) async {
    final user = await _authRecord(table: table, email: email, sanitize: false);
    if (user == null) {
      throw StateError('No account with email "$email" exists in "$table"');
    }

    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );

    final idColumnName = idColumn.name;
    if (idColumnName == null) {
      throw StateError('Missing id column for "$table"');
    }

    final userId = user[idColumnName];
    if (userId is! String) {
      throw StateError('Auth record id not found in "$table"');
    }

    return await _passwordResetRequirement(table: table, userId: userId);
  }

  /// The requirement for one account, or null when it owes nothing.
  ///
  /// Keyed on `(table, user_id)`, which the unique index covers. This sits on
  /// the password sign-in path and will miss for essentially every account in
  /// essentially every deployment (design §3.3) -- so it does one indexed
  /// read and nothing else.
  Future<PasswordResetRequirement?> _passwordResetRequirement({
    required String table,
    required String userId,
  }) async {
    final db = await open();

    final rows = await db
        .select()
        .from(passwordResetRequirements)
        .where(
          passwordResetRequirements.table.equals(table) &
              passwordResetRequirements.userId.equals(UnknownId(userId)),
        )
        .limit(1);

    return rows.singleOrNull;
  }
}

extension _PasswordResetGateX on ZonaiDb {
  /// Refuses a password sign-in that verified, when the account owes a new
  /// password -- handing back a one-time ticket instead of a session.
  ///
  /// Called from [_signInWithPassword] after the password matches and before
  /// anything mints, records or announces a session, so a gated attempt
  /// leaves no JWT, no `_jwt` row, and fires no `onSignIn` extension. An
  /// extension told a sign-in happened would provision, log and notify
  /// against a session that does not exist.
  ///
  /// One insertion point covers `POST /auth/sign-in`, `POST /auth` with
  /// `type: signIn`, and `POST /auth/admin`: all three build a password
  /// payload and land here.
  ///
  /// Deliberately not reached by OTP, magic link or OAuth. The requirement is
  /// a statement about the *password* credential; someone who proved
  /// possession of their mailbox or their Google account has not used the
  /// password and is not asked to change it. It stays unusable until they do.
  Future<void> _refuseIfPasswordResetRequired({
    required String table,
    required Map<String, Object?> user,
  }) async {
    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );
    final emailColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .email),
    );

    final idColumnName = idColumn.name;
    final emailColumnName = emailColumn.name;
    if (idColumnName == null || emailColumnName == null) {
      // Nothing to enforce against: without an id there is no key to look a
      // requirement up by. Falling through lets the sign-in proceed, which is
      // the pre-feature behaviour rather than a new refusal.
      return;
    }

    final userId = user[idColumnName];
    final email = user[emailColumnName];
    if (userId is! String || email is! String) {
      return;
    }

    final requirement = await _passwordResetRequirement(
      table: table,
      userId: userId,
    );
    if (requirement == null) {
      return;
    }

    // A fresh sign-in invalidates any ticket a previous one handed out, and
    // any emailed reset link still in flight. Two live tickets for one
    // account would mean a secret the holder has forgotten about staying
    // good.
    await _expireOldChallenges(
      table: table,
      email: email,
      type: .passwordReset,
    );

    final secret = switch (_insecureTestMode()) {
      true => kInsecureTestResetPasswordSecret,
      false => _randomChallengeSecret(),
    };
    final hashedSecret = await _hashPassword.hash(password: secret);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.passwordReset(
        id: AuthChallengeId.generate(),
        expiresAt: clock.now().add(_forcedResetTicketLifetime),
        secretHash: hashedSecret,
        target: email,
        table: table,
      ),
    ]);

    logger.verbose(
      'Refused sign-in for $userId in "$table": password reset required '
      '(${requirement.reason.name})',
      prefix: _prefix,
    );

    throw PasswordResetRequiredException(
      token: base64Encode('$secret:$email'.codeUnits),
      expiresIn: _forcedResetTicketLifetime,
      reason: requirement.reason,
    );
  }
}

/// Deliberately shorter than the emailed link's configured `expiresIn`. That
/// one has to survive a trip through a mail queue and a person getting round
/// to their inbox; this one is handed to a caller who is at the keyboard
/// right now, so a long life is exposure with nothing bought for it.
const _forcedResetTicketLifetime = Duration(minutes: 15);
