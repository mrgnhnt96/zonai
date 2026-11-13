part of zonai_db;

/// How long a `sessionHandoff` code stays good.
const _sessionHandoffExpiresIn = Duration(minutes: 5);

typedef _SessionHandoff = ({String code, DateTime expiresAt});

/// A signed-in session hands another client -- a command line that cannot
/// sign in by itself, say -- a one-time code, and that client trades the code
/// and its PKCE secret for a session of its own.
///
/// The new session is minted by the same [_createJwt] every sign-in uses,
/// with no `replaces`, so it is its own `_jwt` row: signing out of either
/// session leaves the other alone, and `logoutAll` ends both (the OAuth
/// design's §3.4 holds here unchanged).
extension _SessionHandoffX on ZonaiDb {
  Future<_SessionHandoff> _createSessionHandoff({
    required String? jwt,
    required String codeChallenge,
    required String codeChallengeMethod,
  }) async {
    final caller = await _extractJwt(JwtPayload(jwt: jwt));
    if (caller == null) {
      throw const InvalidJwtException();
    }

    // 256 random bits, stored only as a plain digest so the exchange can find
    // the row by exact match -- as `oauthState` does with its `state`.
    final code = generateOAuthState();
    final expiresAt = clock.now().add(_sessionHandoffExpiresIn);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge.sessionHandoff(
        id: AuthChallengeId.generate(),
        userId: caller.userId,
        expiresAt: expiresAt,
        secretHash: _sha256Hex(code),
        table: caller.table,
        codeChallenge: codeChallenge,
      ),
    ]);

    return (code: code, expiresAt: expiresAt);
  }

  Future<_AuthResult> _exchangeSessionHandoff({
    required String code,
    required String codeVerifier,
  }) async {
    final db = await open();
    final matches = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.secretHash.equals(_sha256Hex(code)) &
              authChallenges.type.equals(AuthChallengeType.sessionHandoff) &
              authChallenges.canConsume.isTrue(),
        )
        .limit(1);
    final challenge = matches.singleOrNull;

    // A code that never existed and one already traded fail alike.
    if (challenge == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'session handoff');
    }

    if (challenge.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'session handoff');
    }

    // Spent before anything else runs, so a failure below still burns it.
    await _consumeChallenge(challenge);

    final userId = challenge.userId;
    if (userId == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'session handoff');
    }

    // By id, as refresh does: the account may have changed its address since
    // the code was made.
    final user = await _authRecordById(
      table: challenge.table,
      userId: userId.value,
    );
    if (user == null) {
      throw UserNotFoundAuthException(table: challenge.table);
    }

    return await _issueSession(
      table: challenge.table,
      user: user,
      extensionStep: .onSignIn,
    );
  }
}
