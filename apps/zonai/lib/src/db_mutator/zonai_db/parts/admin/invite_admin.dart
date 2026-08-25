part of zonai_db;

/// Design §2: 7 days.
const _adminInviteExpiresIn = Duration(days: 7);

/// Everything [ZonaiDb.describeAdminInvite] is allowed to say about a live
/// invite: which `AsAdmin` table it is for, and the sign-in methods that
/// table declares.
///
/// A record rather than a map because the shape is the guarantee. The
/// invited email is deliberately absent and there is no field to put it in
/// — a forged or leaked token must not become a way to learn which address
/// it was issued for. Same reasoning that keeps the token's hash out of
/// [_listAdminInvites].
///
/// `fields` is the columns the accepting invitee has to fill in beyond email
/// and password — `name` on the reference schema. Without them the acceptance
/// screen would collect a password, post it, and get a cast failure from the
/// insert, because a non-nullable column with no value is not something the
/// server can invent. They are schema shapes, not secrets: the same metadata
/// the dashboard's create form already renders.
typedef AdminInviteDescription = ({
  String table,
  List<AuthType> authTypes,
  List<ColumnShape> fields,
});

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

    return await _issueAdminInvite(
      table: table,
      email: email,
      invitedByUserId: appJwt.userId.value,
      invitedByEmail: await _emailFromJwt(table: table, jwt: appJwt),
      throttleResends: true,
    );
  }

  /// `zonai db admin invite` — the same invite, issued by an operator at a
  /// terminal instead of an admin at the dashboard (design §3.1).
  ///
  /// **There is no JWT to check and none is wanted.** A caller who can run
  /// this already holds the database credentials and could insert the admin
  /// row outright; requiring a session would only mean the first admin can
  /// never be invited, which is the bootstrap case `zonai db admin add`
  /// exists for and the one this makes safe — an invite creates no admin row
  /// until the invitee proves the address, where `add` creates one outright.
  /// That is exactly why it must stay a separate entry point from
  /// [_inviteAdmin] rather than a nullable `jwt`: a null that means "root"
  /// on a method the HTTP layer also calls is one missing argument away from
  /// an unauthenticated invite route.
  ///
  /// The invite is attributed to no one. `invitedBy` metadata carries a user
  /// id, the CLI has none, and inventing one would put a fake audit trail on
  /// the record.
  ///
  /// Resends are **not** throttled here. The one-minute limit protects a
  /// mailbox from an admin JWT, which is not the threat model at a shell
  /// that can already write the table; what it would actually catch is an
  /// operator re-running the command after fixing SMTP, which is the most
  /// likely reason to run it twice.
  Future<Map<String, Object?>> _inviteAdminFromCli({
    required String email,
  }) async {
    final (table, _) = await _adminTable();

    return await _issueAdminInvite(
      table: table,
      email: email,
      invitedByUserId: null,
      invitedByEmail: null,
      throttleResends: false,
    );
  }

  /// Mints and mails an invite. Shared by [_inviteAdmin] and
  /// [_inviteAdminFromCli] so the token, its expiry, the resend-not-duplicate
  /// rule and the already-an-admin refusal have one implementation — the
  /// callers differ only in who authorized them and who gets attributed.
  Future<Map<String, Object?>> _issueAdminInvite({
    required String table,
    required String email,
    required String? invitedByUserId,
    required String? invitedByEmail,
    required bool throttleResends,
  }) async {
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

    if (lastInvite case final challenge? when throttleResends) {
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

    final db = await open();
    await db.insert(into: authChallenges).values([
      AuthChallenge(
        id: AuthChallengeId.generate(),
        userId: null,
        expiresAt: expiresAt,
        // Both absent for a CLI invite. An empty map is the honest record of
        // "issued at a terminal by whoever had the credentials"; a
        // placeholder id would read downstream as a real inviter.
        metadata: {
          if (invitedByUserId != null) 'invitedBy': invitedByUserId,
          if (invitedByEmail != null) 'invitedByEmail': invitedByEmail,
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

    courier.sendInBackground(
      SendAdminInviteEmail(
        to: EmailAddress(address: normalizedEmail),
        table: table,
        isResend: lastInvite != null,
        inviteUrl: inviteUrl,
        expiresIn: _adminInviteExpiresIn,
        invitedByEmail: invitedByEmail,
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

  /// Describes an invite **without consuming it** — the read-only lookup the
  /// acceptance screen needs so a stale link can be explained in its own
  /// words instead of as a raw 401 from
  /// `GET /auth/admin/invite/oauth/start/:provider` (design §7).
  ///
  /// Unauthenticated by necessity: the invitee has no session, which is the
  /// entire point of an invite. [token] is the authorization, exactly as it
  /// is for [_startAdminInviteOAuth].
  ///
  /// **Null is the answer for every unusable token, and they must stay
  /// indistinguishable.** Expired, revoked, already-consumed, forged,
  /// truncated — one `null`, no reason attached. A caller that could tell
  /// "expired" from "no such invite" could walk an address list and learn
  /// which addresses have invites pending, which is the same oracle
  /// `_revokeAdminInvite` answers identically to close.
  ///
  /// That is also why every configured admin table is probed even once a
  /// match is in hand: the number of queries this makes is a function of how
  /// many admin tables exist, never of what the token turned out to be.
  ///
  /// [_findLiveAdminInvite] needs a table and a probe has none, so the tables
  /// come from `GetAdminTablesOperationRequest` the way
  /// [_adminSupportedAuthTypes] enumerates them. The `authTypes` returned are
  /// the matched table's own, not the union across every admin table — which
  /// is what lets [_acceptAdminInvite] decide, from this same answer, whether
  /// a password is owed (design §3.3).
  Future<AdminInviteDescription?> _describeAdminInvite({
    required String token,
  }) async {
    final resolved = await _resolveAdminInvite(token: token);
    if (resolved == null) return null;
    return (
      table: resolved.table,
      authTypes: resolved.authTypes,
      fields: await _adminInviteFields(resolved.table),
    );
  }

  /// The columns an accepting invitee must supply, beyond the email the
  /// invite already carries and the password the table may want.
  ///
  /// The same set `zonai db admin add` asks for through `--data`, resolved
  /// the same way, so the two surfaces cannot drift into disagreeing about
  /// what an admin row needs.
  Future<List<ColumnShape>> _adminInviteFields(String table) async {
    final shapes = await _dispatchOperation<AllTableSchemaShapesResponse>(
      GetAllTableSchemaShapesRequest(),
    );

    final shape = shapes.shapes[table];
    if (shape == null) return const [];

    return adminExtraCreateFields(shape.columns);
  }

  /// The lookup behind both [_describeAdminInvite] and [_acceptAdminInvite]:
  /// which table's invite is this, what does that table support, and the
  /// challenge row itself so a caller that means to consume it does not have
  /// to look it up a second time.
  ///
  /// **Every configured admin table is probed even once a match is in hand**,
  /// and the same expiry check runs on each. The number of queries is a
  /// function of how many admin tables exist, never of what the token turned
  /// out to be — an early `return` here would make the response time a side
  /// channel for whether a token matched, which is the oracle the single
  /// `null` in [_describeAdminInvite] exists to close.
  Future<({String table, List<AuthType> authTypes, AuthChallenge invite})?>
  _resolveAdminInvite({required String token}) async {
    final authTables = await _dispatchOperation<AdminTablesResponse>(
      GetAdminTablesOperationRequest(),
    );

    final now = clock.now();
    ({String table, List<AuthType> authTypes, AuthChallenge invite})? found;

    for (final (tableName, authTypes) in authTables.tables) {
      final invite = await _findLiveAdminInvite(token: token, table: tableName);
      if (invite == null) continue;
      if (invite.expiresAt.isBefore(now)) continue;
      found ??= (table: tableName, authTypes: authTypes, invite: invite);
    }

    return found;
  }

  /// Design §3.3: accept an invite on an admin table that signs in with
  /// something other than OAuth — create the row, consume the invite, and
  /// return a session, the same ending [_provisionInvitedAdmin] reaches for
  /// the OAuth case.
  ///
  /// **What authorizes this is the token, and the token alone.** That is a
  /// weaker claim than §3.2's, which additionally requires the provider to
  /// vouch that the signing-in identity owns the invited address — so the
  /// two are not interchangeable and this path refuses an OAuth-only table
  /// ([AdminInviteRequiresOAuthException]) rather than offering a cheaper
  /// way onto it. Where it *is* the right claim, it is the same one
  /// `MagicLinkAuth` already accepts as proof of an address: the token was
  /// mailed to [AuthChallenge.target] and nowhere else, so holding it is
  /// holding that mailbox.
  ///
  /// The row is created in the **invite's** table, not `_adminTable()`'s
  /// first one. They differ the moment a project declares two `AsAdmin`
  /// tables, and creating the admin somewhere other than where they were
  /// invited would be silent.
  ///
  /// Consumption is last. Every refusal above it throws before the row is
  /// created and before [_consumeChallenge] runs, so a rejected attempt
  /// leaves the invite usable (design §4 item 3) — the property that lets
  /// someone who mistypes a password try again instead of needing a fresh
  /// invite.
  Future<_AuthResult> _acceptAdminInvite({
    required String token,
    String? password,
    Map<String, dynamic>? object,
  }) async {
    final resolved = await _resolveAdminInvite(token: token);
    if (resolved == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'admin invite');
    }

    final (:table, :authTypes, :invite) = resolved;

    // OAuth is not *disqualifying* -- a table offering Google and a password
    // can be accepted either way, and the screen shows both. Only a table
    // with nothing but OAuth has to go the other route.
    final directTypes = authTypes.where((type) => type != AuthType.oauth);
    if (directTypes.isEmpty) {
      throw AdminInviteRequiresOAuthException(table: table);
    }

    final supportsPassword = authTypes.contains(AuthType.password);
    if (supportsPassword && (password == null || password.isEmpty)) {
      throw AdminInvitePasswordMismatchException(table: table, required: true);
    }
    if (!supportsPassword && password != null) {
      throw AdminInvitePasswordMismatchException(table: table, required: false);
    }

    // Whatever the table needs beyond email and password -- `name` on the
    // reference schema. Resolved through the same helper `zonai db admin
    // add` uses, so a missing one is the same named refusal there and here
    // rather than a cast failure from the insert. The probe reports this set
    // so the screen can ask for it before submitting.
    final resolvedObject = resolveAdminCreateObject(
      extraFields: await _adminInviteFields(table),
      data: object,
    );

    // `target` is already lowercased at issue time (`_inviteAdmin`), and it
    // -- not anything the caller sent -- is the address the row gets. The
    // request carries no email field at all, so there is nothing to
    // disagree with.
    final user = await _createAdmin(
      inTable: table,
      email: invite.target,
      password: password,
      object: resolvedObject.isEmpty ? null : resolvedObject,
    );

    await _consumeChallenge(invite);

    final (newJwt, sessionToken) = await _createJwt(table, user);

    await _runExtension(
      AuthExtensionRequest.onSignIn(table: table, object: user, jwt: newJwt),
    );

    await _executeEffects();

    logger.verbose(
      'Admin invite accepted for "$table": ${invite.target}',
      prefix: _prefix,
    );

    return (user: user, jwt: sessionToken);
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

    await _expireAdminInvite(table: table, email: email);
  }

  /// `zonai db admin revoke-invite`. Root, for the same reason
  /// [_inviteAdminFromCli] is, and the counterpart to it: the surface that
  /// can issue an invite without a session has to be able to take it back
  /// without one, or a typo'd address stays live for seven days with no way
  /// to cancel it until someone can sign in.
  Future<void> _revokeAdminInviteFromCli({required String email}) async {
    final (table, _) = await _adminTable();
    await _expireAdminInvite(table: table, email: email);
  }

  Future<void> _expireAdminInvite({
    required String table,
    required String email,
  }) async {
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

    return await _pendingAdminInvites(table: table);
  }

  /// `zonai db admin invites`. Root, like its siblings — and the reason the
  /// CLI needs its own: before the first admin exists there is no session
  /// that could list anything, which is precisely when an operator wants to
  /// see whether the invite they sent is still outstanding.
  Future<List<Map<String, Object?>>> _listAdminInvitesFromCli() async {
    final (table, _) = await _adminTable();
    return await _pendingAdminInvites(table: table);
  }

  Future<List<Map<String, Object?>>> _pendingAdminInvites({
    required String table,
  }) async {
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
