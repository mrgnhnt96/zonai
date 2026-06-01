part of zonai_db;

extension _ChallengeX on ZonaiDb {
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
