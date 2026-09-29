part of zonai_db;

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
/// - [_confirmUpgrade] proves the code and writes the address onto the SAME
///   row, so everything the account already owns stays its own.
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

    final (newJwt, token) = await _createJwt(table, user);
    final credential = await _issueAnonymousCredential(
      table: table,
      userId: newJwt.userId,
    );

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
    final last = await _lastChallenge(
      table: table,
      email: address,
      type: .emailChange,
    );
    if (last case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    await _expireOldChallenges(
      table: table,
      email: address,
      type: .emailChange,
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

  Future<_AuthResult> _confirmUpgrade({
    required String? jwt,
    required String email,
    required String code,
    String? password,
  }) async {
    final caller = await _requireAnonymousSession(jwt);
    final table = caller.table;
    final address = _normalizeAddress(email);

    // A code is bound to the session that asked for it. One presented by any
    // other session -- even with the right digits -- is indistinguishable
    // from a wrong code, and costs an attempt like one.
    final challenge = await _lastChallenge(
      table: table,
      email: address,
      type: .emailChange,
    );
    if (challenge == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'upgrade');
    }
    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'upgrade');
    }

    final codeMatches =
        challenge.userId?.value == caller.userId.value &&
        await _hashPassword.verify(
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

    final columns = await _upgradeColumns(table);

    // Case-insensitively: addresses are stored as given, and `Ada@x` and
    // `ada@x` must not become two accounts. Known only to the caller who just
    // proved the mailbox; the anonymous account is left exactly as it was.
    if (await _addressTaken(table, columns.email, address)) {
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
          if (password case final password?)
            if (columns.password case final passwordColumn?)
              ColumnUpdate(
                passwordColumn,
                Literal(await _hashPassword.hash(password: password)),
              ),
        ],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null) {
      throw AuthFailedException(cause: error);
    }
    // `rowsAffected`, not `rows`: an UPDATE returns no rows here (see the
    // read-back in `update.dart`). Zero means the `email IS NULL` guard
    // matched nothing -- someone upgraded this account first, and this
    // session is stale.
    if (result == null || result.rowsAffected == 0) {
      throw const NotAnonymousSessionException();
    }

    // Everything that proved "anonymous" retires together: the device
    // credential (a verified account signs in through its verified channel)
    // and every session, whose `isAnonymous` and `user` snapshot would now be
    // wrong. The caller gets a new session below.
    final db = await open();
    await db
        .delete(from: anonymousCredentials)
        .where(
          anonymousCredentials.table.equals(table) &
              anonymousCredentials.userId.equals(caller.userId),
        );
    await _revokeAllSessions(caller.userId);

    final user = await _authRecordById(
      table: table,
      userId: caller.userId.value,
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
    return name != null && user.containsKey(name) && user[name] == null;
  }

  String _normalizeAddress(String email) => email.trim().toLowerCase();

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
      'SELECT 1 FROM "$table" WHERE LOWER("$emailColumn") = ? LIMIT 1',
      [address],
    ));
    if (error != null) {
      throw AuthFailedException(cause: error);
    }
    return result?.rows.isNotEmpty ?? false;
  }
}
