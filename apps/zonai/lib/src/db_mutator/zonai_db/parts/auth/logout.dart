part of zonai_db;

extension _LogoutX on ZonaiDb {
  Future<void> _logout(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw const InvalidJwtException();
    }

    final db = await open();

    final result = await db
        .delete(from: jwts)
        .where(jwts.id.equals(appJwt.jwtId))
        .returning();

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
