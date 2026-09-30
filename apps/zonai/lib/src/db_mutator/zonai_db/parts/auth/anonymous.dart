part of zonai_db;

/// A confirm that has passed every check and is ready to be written.
typedef _PreparedUpgrade = ({
  Jwt caller,
  String address,
  ({String id, String email, String isVerified, String? password}) columns,
  String? passwordHash,
});

/// What creating an anonymous account hands back: the session, plus the
/// credential that resumes the account once that session has expired. The
/// credential is returned exactly once and never stored in plaintext.
typedef _AnonymousResult = ({
  Map<String, Object?> user,
  String jwt,
  String credential,
});

/// Anonymous accounts: rows of an `AnonymousAuth` table whose email is NULL.
///
/// Four flows, all keyed on the account's id and never on an address:
///
/// - [_signInAnonymously] creates the row and a session, and issues the
///   device credential.
/// - [_resumeAnonymous] trades that credential for a fresh session once the
///   old one has expired -- an anonymous account has no other way back in.
/// - [_requestUpgrade] sends a code to the address the owner wants to adopt,
///   bound to the requesting session.
/// - [_prepareUpgrade] / [_commitUpgrade] prove the code and write the
///   address onto the SAME row, so everything the account already owns stays
///   its own.
///
/// Every email lookup elsewhere is an equality on the email column, and NULL
/// never equals anything, so none of the OTP, magic-link, password or reset
/// flows can reach an anonymous row.
extension _AnonymousX on ZonaiDb {
  static const _credentialPrefix = 'zonai_anon_';

  Future<_AnonymousResult> _signInAnonymously(
    String table, {
    Map<String, Object?>? object,
    String? jwt,
  }) async {
    // One device, one anonymous account. A caller who is already signed in
    // is at the wrong door, as on every other sign-up path.
    if (jwt != null) {
      throw const AlreadyAuthenticatedException();
    }

    await _requireAnonymousAccess(table, .signUp);

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        table: table,
        jwt: null,
        payload: AnonymousAuthOperationPayload.save(object: {...?object}),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? AuthFailedException(cause: 'Failed to create user');
    }

    final user = await _sanitizeRow(table, result.rows.single.toMap());
    logger.verbose('Created anonymous user', prefix: _prefix);

    // The row, its session and its credential are three writes. The
    // credential is the only way back into an address-less account, so a row
    // left without one could never be resumed: it would sit in the table,
    // owned by nobody who can reach it. Undo the row if either later write
    // fails, rather than leave that behind.
    final Jwt newJwt;
    final String token;
    final String credential;
    try {
      (newJwt, token) = await _createJwt(table, user);
      credential = await _issueAnonymousCredential(
        table: table,
        userId: newJwt.userId,
      );
    } on Object {
      await _discardAnonymousRow(table, user);
      rethrow;
    }

    // `beforeSignUp` is deliberately not run here: its candidate carries an
    // address, and this sign-up has none. It runs at upgrade, when there is
    // one to judge. An app that wants to refuse anonymous accounts outright
    // does so in `AuthRowRules.canSignUp(jwt, AuthType.anonymous)`.
    await _runExtension(
      AuthExtensionRequest.onSignUp(table: table, object: user, jwt: newJwt),
    );
    await _executeEffects();

    return (user: user, jwt: token, credential: credential);
  }

  Future<_AuthResult> _resumeAnonymous(String credential) async {
    // Tested on the shape first, like an API token, so nothing that is not a
    // credential reaches the lookup. Unknown, malformed and retired all answer
    // the same InvalidJwtException -- you must already hold the secret to ask.
    if (!credential.startsWith(_credentialPrefix)) {
      throw const InvalidJwtException();
    }

    final db = await open();
    final rows = await db
        .select()
        .from(anonymousCredentials)
        .where(
          anonymousCredentials.secretHash.equals(_hashCredential(credential)),
        );
    final row = rows.singleOrNull;
    if (row == null) {
      throw const InvalidJwtException();
    }

    await _requireAnonymousAccess(row.table, .signIn);

    // The credential outlives nothing it should: an upgraded or deleted
    // account no longer answers to it.
    final user = await _authRecordById(
      table: row.table,
      userId: row.userId.value,
    );
    if (user == null || !await _isAnonymousRow(row.table, user)) {
      throw const InvalidJwtException();
    }

    await db
        .update(anonymousCredentials)
        .set(anonymousCredentials.lastUsedAt.to(clock.now()))
        .where(anonymousCredentials.id.equals(row.id));

    return await _issueSession(
      table: row.table,
      user: user,
      extensionStep: .onRefresh,
    );
  }

  Future<void> _requestUpgrade({
    required String? jwt,
    required String email,
  }) async {
    final caller = await _requireAnonymousSession(jwt);
    final table = caller.table;
    final address = _normalizeAddress(email);

    // Before the code is sent, as on OTP sign-up: this is the moment the
    // account acquires an address, so allowlists and invite gates apply here.
    await _runSignUpGate(table, email: address, object: null, jwt: caller);

    // Deliberately no check for whether the address is taken. Answering
    // differently here would tell anyone holding a cheap anonymous session
    // which addresses have accounts; only the mailbox owner learns it, at
    // confirm, after proving they read the code.
    //
    // Keyed by (user, address), not by address alone: another anonymous
    // session must not be able to expire this one's code, hold its cooldown
    // or burn its attempts.
    final last = await _lastUpgradeChallenge(
      table: table,
      address: address,
      userId: caller.userId,
    );
    if (last case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    await _expireUpgradeChallenges(
      table: table,
      address: address,
      userId: caller.userId,
    );

    final expiresIn = const Duration(minutes: 10);
    final code = switch (_insecureTestMode()) {
      true => kInsecureTestOtp,
      false => Random.secure().nextInt(1000000).toString().padLeft(6, '0'),
    };

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.emailChange(
        id: AuthChallengeId.generate(),
        userId: caller.userId,
        expiresAt: clock.now().add(expiresIn),
        secretHash: await _hashPassword.hash(password: code),
        target: address,
        table: table,
      ),
    ]);

    courier.sendInBackground(
      SendOtpEmail(
        to: EmailAddress(address: address),
        table: table,
        isResend: last != null,
        code: code,
        expiresIn: expiresIn,
        variables: null,
      ),
    );
  }

  /// Everything slow in a confirm, OFF the single-writer queue: resolving
  /// the session, the Argon2 check of the code, the app's `beforeSignUp`
  /// hook and hashing a new password. [_commitUpgrade] writes the result on
  /// the queue.
  Future<_PreparedUpgrade> _prepareUpgrade({
    required String? jwt,
    required String email,
    required String code,
    String? password,
  }) async {
    final caller = await _requireAnonymousSession(jwt);
    final table = caller.table;
    final address = _normalizeAddress(email);

    // Looked up as THIS user's challenge: a code another session asked for
    // is not found here, and that session's wrong guesses never reach this
    // one's attempts.
    final challenge = await _lastUpgradeChallenge(
      table: table,
      address: address,
      userId: caller.userId,
    );
    if (challenge == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'upgrade');
    }
    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'upgrade');
    }

    final codeMatches = await _hashPassword.verify(
      rawPassword: code,
      passwordHash: challenge.secretHash,
    );
    if (!codeMatches) {
      await _challengeFailed(challenge);
      throw const InvalidOrExpiredCodeException(codeType: 'upgrade');
    }

    // Again at confirm, as OTP sign-up runs it at verify: the gate is AT
    // LEAST ONCE for this flow, and a hook body must tolerate that.
    await _runSignUpGate(table, email: address, object: null, jwt: caller);
    await _consumeChallenge(challenge);

    return (
      caller: caller,
      address: address,
      columns: await _upgradeColumns(table),
      passwordHash: switch (password) {
        final password? => await _hashPassword.hash(password: password),
        null => null,
      },
    );
  }

  /// The write half of a confirm, ON the single-writer queue: the "is this
  /// address taken" check and the write must not interleave with another
  /// upgrade or a resume, and nothing slow happens here.
  Future<void> _commitUpgrade(_PreparedUpgrade upgrade) async {
    final (:caller, :address, :columns, :passwordHash) = upgrade;
    final table = caller.table;

    // Addresses are stored lowercased (the email column's normalizer), and
    // [address] is too, so this is a plain equality. Known only to the caller
    // who just proved the mailbox; the anonymous account is left exactly as
    // it was.
    if (!debugSkipUpgradeAddressCheck &&
        await _addressTaken(table, columns.email, address)) {
      throw const EmailInUseException();
    }

    final operation = await _dispatchOperation<PerformOperationResponse>(
      UpdateOperationRequest(
        table: table,
        jwt: null,
        // `email IS NULL`: a replayed or concurrent confirm finds nothing to
        // update rather than overwriting an address already written.
        where: And([
          Eq(columns.id, caller.userId.value),
          Where.isNull(columns.email),
        ]),
        updates: [
          ColumnUpdate(columns.email, Literal(address)),
          ColumnUpdate(columns.isVerified, Literal(true)),
          if (passwordHash != null)
            if (columns.password case final passwordColumn?)
              ColumnUpdate(passwordColumn, Literal(passwordHash)),
        ],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null) {
      // The check above runs on the writer queue, but OTP and password
      // sign-up do not, so one can insert the address between the check and
      // this write. A unique email index then refuses the write; that is the
      // same answer the check would have given, so give it.
      if (mapDatabaseError(error, table: table) is UniqueConstraintException) {
        throw const EmailInUseException();
      }
      throw AuthFailedException(cause: error);
    }
    // `rowsAffected`, not `rows`: an UPDATE returns no rows here (see the
    // read-back in `update.dart`). Zero means the `email IS NULL` guard
    // matched nothing -- someone upgraded this account first, and this
    // session is stale.
    if (result == null || result.rowsAffected == 0) {
      throw const NotAnonymousSessionException();
    }

    // Everything that proved "anonymous" retires in the same queue slot as
    // the write, so no resume can slip between them: the device credential
    // (a verified account signs in through its verified channel) and every
    // session, whose `isAnonymous` and `user` snapshot would now be wrong.
    final db = await open();
    await db
        .delete(from: anonymousCredentials)
        .where(
          anonymousCredentials.table.equals(table) &
              anonymousCredentials.userId.equals(caller.userId),
        );
    await _revokeAllSessions(caller.userId);
  }

  /// The upgraded account's new session. Off the queue: it runs the app's
  /// `onSignIn` hook.
  Future<_AuthResult> _upgradedSession(_PreparedUpgrade upgrade) async {
    final table = upgrade.caller.table;
    final user = await _authRecordById(
      table: table,
      userId: upgrade.caller.userId.value,
    );
    if (user == null) {
      throw UserNotFoundAuthException(table: table);
    }

    return await _issueSession(
      table: table,
      user: user,
      extensionStep: .onSignIn,
    );
  }

  Future<AuthChallenge?> _lastUpgradeChallenge({
    required String table,
    required String address,
    required UnknownId userId,
  }) async {
    final db = await open();
    final rows = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.target.equals(address) &
              authChallenges.table.equals(table) &
              authChallenges.type.equals(AuthChallengeType.emailChange) &
              authChallenges.userId.equals(userId) &
              authChallenges.canConsume.isTrue() &
              authChallenges.allowedAttempts.greaterThan(0),
        )
        .limit(1);
    return rows.singleOrNull;
  }

  Future<void> _expireUpgradeChallenges({
    required String table,
    required String address,
    required UnknownId userId,
  }) async {
    final db = await open();
    await db
        .update(authChallenges)
        .set(
          authChallenges.canConsume.to(false),
          authChallenges.allowedAttempts.to(0),
        )
        .where(
          authChallenges.target.equals(address) &
              authChallenges.table.equals(table) &
              authChallenges.type.equals(AuthChallengeType.emailChange) &
              authChallenges.userId.equals(userId) &
              authChallenges.canConsume.isTrue(),
        );
  }

  /// The caller's validated session, which must be an anonymous one.
  Future<Jwt> _requireAnonymousSession(String? jwt) async {
    final caller = await _extractJwt(JwtPayload(jwt: jwt));
    if (caller == null) {
      throw const InvalidJwtException();
    }
    if (!caller.isAnonymous) {
      throw const NotAnonymousSessionException();
    }
    return caller;
  }

  /// Both halves of the auth rules for [AuthType.anonymous]: the table must
  /// allow anonymous authentication at all, and the row rules must allow this
  /// [operation] -- `signUp` to create, `signIn` to resume.
  Future<void> _requireAnonymousAccess(
    String table,
    AuthOperation operation,
  ) async {
    final tableRules = await _dispatchRules<AuthTableRulesResponse>(
      AuthTableRulesRequest(table: table, jwt: null, authType: .anonymous),
    );
    if (tableRules case AuthTableRulesResponse(canAuthenticate: false)) {
      throw AuthTableNotFoundException(table: table);
    }

    final rowRules = await _dispatchRules<AuthRowRulesResponse>(
      AuthRowRulesRequest(
        table: table,
        jwt: null,
        operation: operation,
        authType: .anonymous,
      ),
    );
    if (rowRules case AuthRowRulesResponse(canAccess: true)) {
      return;
    }

    throw TableAccessDeniedException(table: table, operation: operation.name);
  }

  Future<String> _issueAnonymousCredential({
    required String table,
    required UnknownId userId,
  }) async {
    if (debugFailAnonymousCredentialIssue) {
      throw StateError('debugFailAnonymousCredentialIssue');
    }
    final credential = '$_credentialPrefix${_randomChallengeSecret()}';

    final db = await open();
    await db.insert(into: anonymousCredentials).values([
      AnonymousCredential(
        id: AnonymousCredentialId.generate(),
        table: table,
        userId: userId,
        secretHash: _hashCredential(credential),
      ),
    ]);

    return credential;
  }

  /// Removes an anonymous row whose credential could not be issued, and any
  /// session already minted for it. Best effort: the original failure is
  /// what the caller hears about, so a failure here is logged, not thrown.
  Future<void> _discardAnonymousRow(
    String table,
    Map<String, Object?> user,
  ) async {
    try {
      final idColumn = await _dispatchOperation<ColumnNameResponse>(
        GetColumnNameRequest(table: table, columnName: .id),
      );
      final id = switch (idColumn.name) {
        final name? => user[name],
        null => null,
      };
      if (id is! String) return;

      await _revokeAllSessions(UnknownId(id));
      final (error, _) = await _execute((
        'DELETE FROM "$table" WHERE "${idColumn.name}" = ? AND '
            '"${(await _upgradeColumns(table)).email}" IS NULL',
        [id],
      ));
      if (error != null) throw error;
    } on Object catch (error, stack) {
      logger.error(
        'Could not remove an anonymous row left without a credential',
        error,
        stack,
      );
    }
  }

  /// SHA-256 rather than Argon2 for the reason `_api_tokens` gives: the input
  /// is 256 bits of CSPRNG output, so there is no dictionary to run.
  String _hashCredential(String credential) =>
      sha256.convert(utf8.encode(credential)).toString();

  /// An anonymous row is exactly a row whose email is NULL: the operations
  /// worker refuses a nullable email column on any table that is not
  /// `AnonymousAuth`, so NULL has no other meaning.
  Future<bool> _isAnonymousRow(String table, Map<String, Object?> user) async {
    final emailColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .email),
    );
    final name = emailColumn.name;
    // Fails closed: a row read through an app operation that left the
    // column out counts as anonymous, not as verified.
    return name != null && user[name] == null;
  }

  /// The address as the email column will store it: lowercased, exactly as
  /// the column's `.lowercase()` normalizer folds it, and nothing more. Not
  /// trimmed, because sign-in does not trim: an address normalized here in a
  /// way the sign-in lookup does not repeat could be upgraded to and then
  /// never signed in with.
  String _normalizeAddress(String email) => email.toLowerCase();

  Future<({String id, String email, String isVerified, String? password})>
  _upgradeColumns(String table) async {
    Future<String?> name(ColumnName column) async {
      final response = await _dispatchOperation<ColumnNameResponse>(
        GetColumnNameRequest(table: table, columnName: column),
      );
      return response.name;
    }

    final id = await name(.id);
    final email = await name(.email);
    final isVerified = await name(.isVerified);
    if (id == null || email == null || isVerified == null) {
      throw StateError('"$table" lacks the columns an upgrade writes');
    }

    return (
      id: id,
      email: email,
      isVerified: isVerified,
      password: await name(.password),
    );
  }

  Future<bool> _addressTaken(
    String table,
    String emailColumn,
    String address,
  ) async {
    // Column and table names come from the registered schema and the
    // server-issued token, never from the request body.
    final (error, result) = await _execute((
      'SELECT 1 FROM "$table" WHERE "$emailColumn" = ? LIMIT 1',
      [address],
    ));
    if (error != null) {
      throw AuthFailedException(cause: error);
    }
    return result?.rows.isNotEmpty ?? false;
  }
}

/// Makes the next anonymous sign-ups fail at the credential step, after the
/// row and its session are written -- the failure [_AnonymousX._discardAnonymousRow]
/// exists to clean up after, and which nothing else can produce on demand.
@visibleForTesting
bool debugFailAnonymousCredentialIssue = false;

/// Skips the upgrade's "address already taken" check, so a test can make the
/// write itself meet the unique index -- the race with a concurrent sign-up
/// that the check cannot close.
@visibleForTesting
bool debugSkipUpgradeAddressCheck = false;
