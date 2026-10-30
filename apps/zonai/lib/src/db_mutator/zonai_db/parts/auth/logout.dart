part of zonai_db;

extension _LogoutX on ZonaiDb {
  Future<void> _logout(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw const InvalidJwtException();
    }

    final db = await open();

    // A refresh keeps the session it extends until the new token is used
    // ([JwtEntry.replaces]), so signing out drops both sides of a refresh
    // still in flight: the sessions refreshed from this one, whose replies may
    // have been lost, and the one this was refreshed from.
    final result = await db
        .delete(from: jwts)
        .where(
          jwts.id.equals(appJwt.jwtId) | jwts.replaces.equals(appJwt.jwtId),
        )
        .returning();

    for (final session in result) {
      if (session.id.value != appJwt.jwtId.value) continue;
      if (session.replaces case final replaced?) {
        await db.delete(from: jwts).where(jwts.id.equals(replaced));
      }
    }

    if (result.isEmpty) {
      logger.verbose('No JWT record found', prefix: _prefix);
      return;
    }

    logger.verbose('Logged out: ${appJwt.userId}', prefix: _prefix);

    await _runExtension(
      AuthExtensionRequest.onLogout(
        table: appJwt.table,
        object: appJwt.user,
        jwt: appJwt,
      ),
    );

    await _executeEffects();
  }

  Future<void> _logoutAll(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw const InvalidJwtException();
    }

    final revoked = await _revokeAllSessions(appJwt.userId);

    if (revoked == 0) {
      logger.verbose('No JWT records found', prefix: _prefix);
      return;
    }

    logger.verbose(
      'Logged out all: ${appJwt.userId} ($revoked)',
      prefix: _prefix,
    );
  }

  /// Deletes every `_jwt` row for [userId] -- the same revocation [_logoutAll]
  /// performs for a self-service "log out everywhere", reused by admin
  /// removal (design §3.4) so an admin removed while signed in can't keep a
  /// working JWT until it expires.
  Future<int> _revokeAllSessions(UnknownId userId) async {
    final db = await open();

    final results = await db
        .delete(from: jwts)
        .where(jwts.userId.equals(userId))
        .returning();

    return results.length;
  }
}
