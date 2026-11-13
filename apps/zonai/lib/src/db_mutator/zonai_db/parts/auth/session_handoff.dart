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
    required String table,
    required String codeChallenge,
    required String codeChallengeMethod,
  }) async {
    // Only an ordinary zonai session for a real account may hand itself off.
    // Each refusal below runs before a row is written.
    if (jwt == null) {
      throw const InvalidJwtException();
    }
    if (ApiTokenSecret.looksLike(jwt)) {
      throw const ApiTokenNotAcceptedHereException();
    }
    // Checked against zonai's own key first, so a token from an outside
    // identity provider is refused here rather than resolved -- resolving one
    // can provision an account on first sight, and the session the code buys
    // would then outlive the provider's own revocation.
    if (await _jwt.verify(jwt) == null) {
      throw const InvalidJwtException();
    }
    final caller = await _extractJwt(JwtPayload(jwt: jwt));
    if (caller == null) {
      throw const InvalidJwtException();
    }
    if (caller.admin.isAdmin) {
      throw const SessionHandoffNotAllowedException(
        'admin sessions cannot be handed off',
      );
    }
    if (caller.isAnonymous) {
      throw const SessionHandoffNotAllowedException(
        'anonymous sessions cannot be handed off',
      );
    }
    // The request's table keys the rate limit, so it must be the caller's
    // own; otherwise rotating it would hand each request a fresh counter.
    if (caller.table != table) {
      throw const SessionHandoffNotAllowedException(
        'the session is not signed in to that table',
      );
    }
    if (codeChallengeMethod != 'S256') {
      throw InvalidBodyException(
        'codeChallengeMethod must be S256, not $codeChallengeMethod',
      );
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
    required String table,
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
              authChallenges.table.equals(table) &
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

    // Spent before anything else runs, so a failure below still burns it --
    // a wrong verifier included, so whoever holds a stolen code gets one try.
    await _consumeChallenge(challenge);

    if (!_handoffVerifierMatches(
      codeVerifier: codeVerifier,
      codeChallenge: challenge.metadata?['codeChallenge'],
    )) {
      throw const InvalidOrExpiredCodeException(codeType: 'session handoff');
    }

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

  /// Whether [codeVerifier] is the secret behind [codeChallenge] under PKCE
  /// S256: `base64url(sha256(verifier))` without padding (RFC 7636 §4.6).
  ///
  /// Compared in constant time, so the time a wrong guess takes says nothing
  /// about how much of it was right.
  bool _handoffVerifierMatches({
    required String codeVerifier,
    required Object? codeChallenge,
  }) {
    if (codeChallenge is! String) return false;

    final expected = utf8.encode(codeChallenge);
    final actual = utf8.encode(
      base64Url
          .encode(sha256.convert(utf8.encode(codeVerifier)).bytes)
          .replaceAll('=', ''),
    );
    if (expected.length != actual.length) return false;

    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ actual[i];
    }
    return diff == 0;
  }
}
