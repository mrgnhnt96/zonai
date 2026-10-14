part of zonai_db;

extension _ChallengeX on ZonaiDb {
  /// The one-minute resend cooldown for an address that has no account.
  ///
  /// A send to an existing account is refused with [AuthRateLimitException]
  /// while its last challenge is under a minute old. A send that quietly
  /// skips an unknown address writes no challenge, so it has to keep the same
  /// cooldown here, or a second request tells the two apart.
  void _holdSendWithoutAccount({
    required String table,
    required String email,
    required AuthChallengeType type,
  }) {
    final now = clock.now();
    final cutoff = now.subtract(const Duration(minutes: 1));

    // Drop entries past the cooldown so the map only ever holds the last
    // minute of addresses.
    _sendsWithoutAccount.removeWhere((_, at) => !at.isAfter(cutoff));

    final key = '${type.name}\x00$table\x00$email';
    if (_sendsWithoutAccount.containsKey(key)) {
      throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
    }

    _sendsWithoutAccount[key] = now;
  }

  Future<void> _challengeFailed(AuthChallenge challenge) async {
    final db = await open();

    await db
        .update(authChallenges)
        .set(authChallenges.allowedAttempts.to(challenge.allowedAttempts - 1))
        .where(authChallenges.id.equals(challenge.id));
  }

  Future<void> _consumeChallenge(AuthChallenge challenge) async {
    final db = await open();

    await db
        .update(authChallenges)
        .set(
          authChallenges.consumedAt.to(clock.now()),
          authChallenges.canConsume.to(false),
        )
        .where(authChallenges.id.equals(challenge.id));
  }

  Future<AuthChallenge?> _lastChallenge({
    required String? table,
    required String email,
    required AuthChallengeType type,
  }) async {
    final db = await open();

    Filter where =
        authChallenges.target.equals(email) &
        authChallenges.type.equals(type) &
        authChallenges.canConsume.isTrue() &
        authChallenges.allowedAttempts.greaterThan(0);

    if (table != null) {
      where = where & authChallenges.table.equals(table);
    }

    // must wait 1 minute before sending a new OTP
    final lastOtp = await db
        .select()
        .from(authChallenges)
        .where(where)
        .limit(1);

    return lastOtp.singleOrNull;
  }

  Future<void> _expireOldChallenges({
    required String table,
    required String email,
    required AuthChallengeType type,
  }) async {
    final db = await open();

    // expire all old opts for this email
    await db
        .update(authChallenges)
        .set(
          authChallenges.canConsume.to(false),
          authChallenges.allowedAttempts.to(0),
        )
        .where(
          authChallenges.target.equals(email) &
              authChallenges.table.equals(table) &
              authChallenges.type.equals(type) &
              authChallenges.canConsume.isTrue(),
        );
  }
}
