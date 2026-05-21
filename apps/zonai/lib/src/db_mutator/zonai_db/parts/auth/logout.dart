part of zonai_db;

extension _LogoutX on ZonaiDb {
  Future<void> _logout(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw StateError('Invalid JWT');
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

    await _extensions.send<NoActionExtensionResponse>(
      AuthExtensionRequest.onLogout(
        collection: appJwt.collection,
        object: appJwt.user,
        jwt: appJwt,
      ),
    );

    await _executeEffects();
  }

  Future<void> _logoutAll(String jwt) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null) {
      throw StateError('Invalid JWT');
    }

    final db = await open();

    final results = await db
        .delete(from: jwts)
        .where(jwts.userId.equals(appJwt.userId))
        .returning();

    if (results.isEmpty) {
      logger.verbose('No JWT records found', prefix: _prefix);
      return;
    }

    logger.verbose(
      'Logged out all: ${appJwt.userId} (${results.length})',
      prefix: _prefix,
    );
  }
}
