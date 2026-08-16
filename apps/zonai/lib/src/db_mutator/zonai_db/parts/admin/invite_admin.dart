part of zonai_db;

/// Design §2: 7 days.
const _adminInviteExpiresIn = Duration(days: 7);

extension _InviteAdminX on ZonaiDb {
  /// Caller's JWT must be admin *on the resolved `AsAdmin` table* -- not
  /// merely `isAdmin` against some other collection a multi-admin-table
  /// project might also have (design §3.1, §4 item 1). `jwt.admin.isAdmin`
  /// is already scoped to the JWT's own table (`db_operations.dart`'s
  /// `_getJwtConfig`), but [_adminTable] only ever resolves the *first*
  /// configured `AsAdmin` table -- an admin JWT for a different one must not
  /// pass here.
  Future<Jwt> _requireAdminJwtForResolvedTable({
    required String jwt,
    required String table,
    required String operation,
  }) async {
    final appJwt = await _extractJwt(JwtPayload(jwt: jwt));
    if (appJwt == null || !appJwt.admin.isAdmin || appJwt.table != table) {
      throw TableAccessDeniedException(table: table, operation: operation);
    }
    return appJwt;
  }

  Future<Map<String, Object?>> _inviteAdmin({
    required String email,
    required String jwt,
  }) async {
    final (table, _) = await _adminTable();
    final appJwt = await _requireAdminJwtForResolvedTable(
      jwt: jwt,
      table: table,
      operation: 'inviteAdmin',
    );

    final normalizedEmail = email.toLowerCase();

    final existingAdmin = await _authRecord(
      table: table,
      email: normalizedEmail,
      sanitize: false,
    );
    if (existingAdmin != null) {
      throw StateError(
        'An admin account with email "$normalizedEmail" already exists',
      );
    }

    final lastInvite = await _lastChallenge(
      table: table,
      email: normalizedEmail,
      type: .adminInvite,
    );

    if (lastInvite case final challenge?) {
      if (challenge.createdAt.isAfter(
        clock.now().subtract(const Duration(minutes: 1)),
      )) {
        throw const AuthRateLimitException(waitDuration: Duration(minutes: 1));
      }
    }

    // A live invite is resent, not duplicated -- same `isResend` shape
    // `_sendMagicLink` uses: expire the old one and mint a fresh token
    // rather than leaving two pending rows for the same email (design
    // §3.1).
    await _expireOldChallenges(
      table: table,
      email: normalizedEmail,
      type: .adminInvite,
    );

    final token = switch (kIsCompiled) {
      false => 'dev-admin-invite',
      true => List.generate(
        32,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    };

    final expiresAt = clock.now().add(_adminInviteExpiresIn);
    final inviterEmail = await _emailFromJwt(table: table, jwt: appJwt);

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge(
        id: AuthChallengeId.generate(),
        userId: null,
        expiresAt: expiresAt,
        metadata: {
          'invitedBy': appJwt.userId.value,
          if (inviterEmail != null) 'invitedByEmail': inviterEmail,
        },
        secretHash: _sha256Hex(token),
        target: normalizedEmail,
        table: table,
        type: .adminInvite,
        allowedAttempts: 1,
      ),
    ]);

    final appConfig = await configResolver.resolve();
    final base = appConfig.baseUrl.endsWith('/')
        ? appConfig.baseUrl.substring(0, appConfig.baseUrl.length - 1)
        : appConfig.baseUrl;
    final inviteUrl =
        '$base/_/admin/invite?token=${Uri.encodeComponent(token)}';

    courier.send(
      SendAdminInviteEmail(
        to: EmailAddress(address: normalizedEmail),
        table: table,
        isResend: lastInvite != null,
        inviteUrl: inviteUrl,
        expiresIn: _adminInviteExpiresIn,
        invitedByEmail: inviterEmail,
      ),
    );

    logger.verbose(
      'Invited admin for "$table": $normalizedEmail',
      prefix: _prefix,
    );

    return {
      'email': normalizedEmail,
      'table': table,
      'expiresAt': expiresAt.toIso8601String(),
      'isResend': lastInvite != null,
    };
  }

  Future<void> _revokeAdminInvite({
    required String email,
    required String jwt,
  }) async {
    final (table, _) = await _adminTable();
    await _requireAdminJwtForResolvedTable(
      jwt: jwt,
      table: table,
      operation: 'revokeAdminInvite',
    );

    final normalizedEmail = email.toLowerCase();
    await _expireOldChallenges(
      table: table,
      email: normalizedEmail,
      type: .adminInvite,
    );

    logger.verbose(
      'Revoked admin invite for "$table": $normalizedEmail',
      prefix: _prefix,
    );
  }

  /// Pending means unconsumed (`canConsume`, which revoke also clears) and
  /// unexpired (design §3.4) -- never the secret hash, matching how
  /// [_listAdmins] never returns a password hash (design §4 item 10).
  Future<List<Map<String, Object?>>> _listAdminInvites({
    required String jwt,
  }) async {
    final (table, _) = await _adminTable();
    await _requireAdminJwtForResolvedTable(
      jwt: jwt,
      table: table,
      operation: 'listAdminInvites',
    );

    final db = await open();
    final rows = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.table.equals(table) &
              authChallenges.type.equals(.adminInvite) &
              authChallenges.canConsume.isTrue(),
        );

    final now = clock.now();
    return [
      for (final row in rows)
        if (row.expiresAt.isAfter(now))
          {
            'email': row.target,
            'invitedAt': row.createdAt.toIso8601String(),
            'expiresAt': row.expiresAt.toIso8601String(),
            'invitedByEmail': (row.metadata ?? const {})['invitedByEmail'],
          },
    ];
  }
}
