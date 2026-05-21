part of zonai_db;

extension _ChallengeX on ZonaiDb {
  Future<void> _consumeChallenge(AuthChallenge challenge) async {
    final db = await open();

    await db
        .update(authChallenges)
        .set(
          authChallenges.consumedAt.to(clock.now()),
          authChallenges.canConsume.to(false),
        )
        .where(authChallenges.id.equals(challenge.id.value));
  }

  Future<AuthChallenge?> _lastChallenge({
    required String collection,
    required String email,
  }) async {
    final db = await open();

    // must wait 1 minute before sending a new OTP
    final lastOtp = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.target.equals(email) &
              authChallenges.collection.equals(collection) &
              authChallenges.canConsume.isTrue(),
        )
        .limit(1);

    return lastOtp.singleOrNull;
  }

  Future<void> _expireOldChallenges({
    required String collection,
    required String email,
    required AuthChallengeType type,
  }) async {
    final db = await open();

    // expire all old opts for this email
    await db
        .update(authChallenges)
        .set(authChallenges.canConsume.to(false))
        .where(
          authChallenges.target.equals(email) &
              authChallenges.collection.equals(collection) &
              authChallenges.type.equals(type) &
              authChallenges.canConsume.isTrue(),
        );
  }
}
