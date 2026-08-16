part of zonai_db;

/// How long an `_auth_challenges` row of type `oauthState` stays valid.
/// Design §4 item 1: ≤10 minutes.
const _oauthStateExpiresIn = Duration(minutes: 10);

typedef _OAuthCallbackResult = ({
  Map<String, Object?> user,
  String jwt,
  String? redirectTo,
});

/// Server-driven redirect flow (§3.1), native/public-client flow (§3.2), and
/// identity resolution (§3.3) for `OAuth`-mixed-in auth tables.
///
/// Everything here ends in the same rails `external_idp.dart` uses: identity
/// resolution reaches the *same* `AuthExtensionRequest.onExternalAuthFirstSeen`
/// hook and `externalIdpProvisioningGate` via [_provisionOAuthUser], and
/// session minting reaches the *same* [_createJwt] via [_finishOAuthSignIn].
/// See `docs/oauth-design.md` §3.
extension _OAuthX on ZonaiDb {
  // ---------------------------------------------------------------------
  // Provider listing (design §2.4 / item 4: "an operation exposing
  // OAuthProviderPublic per table").
  // ---------------------------------------------------------------------

  Future<List<OAuthProviderPublic>> _oauthProviders() async {
    final response = await _dispatchOperation<OAuthProvidersResponse>(
      GetOAuthProvidersOperationRequest(),
    );
    return response.providers;
  }

  // ---------------------------------------------------------------------
  // §3.1 step 1 — start.
  // ---------------------------------------------------------------------

  Future<String> _startOAuth(
    String table,
    StartOAuthAuthPayload payload, {
    bool isAdmin = false,
    String? inviteToken,
  }) async {
    logger.setTraceProps({
      'op': 'oauth_start',
      'table': table,
      'provider': payload.provider,
    });
    var step = 'start';
    logger.trace('start');
    try {
      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'resolve_provider';
      final provider = await _resolveOAuthProvider(table, payload.provider);
      logger.trace('resolve_provider');

      step = 'redirect_check';
      final appConfig = await getConfig();
      final redirectTo = payload.redirectTo;
      if (redirectTo != null &&
          !_isAllowedOAuthRedirect(redirectTo, appConfig)) {
        throw OAuthRedirectNotAllowedException(redirectTo: redirectTo);
      }
      logger.trace('redirect_check');

      // `state`/`verifier`/`nonce` are ≥256-bit random (design §4 item 1)
      // and never logged past this point — only step names and booleans are.
      step = 'mint_challenge';
      final state = generateOAuthState();
      final verifier = generatePkceCodeVerifier();
      final nonce = generateOAuthNonce();
      // Deterministic (unlike `_hashPassword.hash`'s salted Argon2 output)
      // so the callback can look the challenge up by exact hash match --
      // `state` is high-entropy and single-use, so a plain digest carries
      // no meaningful rainbow-table/timing risk the way a 6-digit OTP would.
      final hashedState = _sha256Hex(state);

      final db = await open();
      await db.insert(into: authChallenges).values([
        AuthChallenge.oauthState(
          id: AuthChallengeId.generate(),
          expiresAt: clock.now().add(_oauthStateExpiresIn),
          secretHash: hashedState,
          target: payload.provider,
          table: table,
          metadata: {
            'verifier': verifier,
            'nonce': nonce,
            'isAdmin': isAdmin,
            if (redirectTo != null) 'redirectTo': redirectTo,
            if (inviteToken != null) 'inviteToken': inviteToken,
          },
        ),
      ]);
      logger.trace('mint_challenge');

      step = 'build_url';
      final redirectUri = _oauthRedirectUri(appConfig, payload.provider);
      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: redirectUri,
        state: state,
        codeChallenge: derivePkceCodeChallenge(verifier),
        nonce: nonce,
      );
      logger.trace('done');
      return url;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Admin-invite counterpart of [_startOAuth] (design §3.2 step 3): resolves
  /// the `AsAdmin` table configured for `AuthType.oauth` the same way
  /// [ZonaiDb.startAdminOAuth] does, fails fast when [inviteToken] doesn't
  /// name a live invite rather than deferring every error to the callback,
  /// and carries the token into the minted `oauthState` challenge's metadata
  /// so [_completeOAuthCallback] knows an invite is in play.
  Future<String> _startAdminInviteOAuth({
    required String inviteToken,
    required StartOAuthAuthPayload payload,
  }) async {
    final table = await _adminCollectionFor(.oauth);

    final invite = await _findLiveAdminInvite(token: inviteToken, table: table);
    if (invite == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'admin invite');
    }
    if (invite.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'admin invite');
    }

    return await _startOAuth(
      table,
      payload,
      isAdmin: true,
      inviteToken: inviteToken,
    );
  }

  // ---------------------------------------------------------------------
  // §3.1 step 2 — callback.
  // ---------------------------------------------------------------------

  Future<_OAuthCallbackResult> _completeOAuthCallback(
    CompleteOAuthAuthPayload payload,
  ) async {
    logger.setTraceProps({'op': 'oauth_callback'});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'find_challenge';
      final hashedState = _sha256Hex(payload.state);
      final db = await open();
      final matches = await db
          .select()
          .from(authChallenges)
          .where(
            authChallenges.secretHash.equals(hashedState) &
                authChallenges.type.equals(.oauthState) &
                authChallenges.canConsume.isTrue(),
          )
          .limit(1);
      final challenge = matches.singleOrNull;
      logger.trace('find_challenge', extra: {'found': challenge != null});

      // Single-use, replay rejected (design §4 item 1): a state hash with
      // no matching *consumable* row -- because it never existed, or
      // because a prior request already consumed it -- fails identically.
      if (challenge == null) {
        throw const InvalidOrExpiredCodeException(codeType: 'OAuth state');
      }

      if (challenge.expiresAt.isBefore(clock.now())) {
        throw const CodeExpiredException(codeType: 'OAuth state');
      }

      // Consumed before any external call: a crashed or duplicated request
      // can never replay the same `state` twice, regardless of what the
      // token exchange below does.
      step = 'consume_challenge';
      await _consumeChallenge(challenge);
      logger.trace('consume_challenge');

      final table = challenge.table;
      final providerId = challenge.target;
      final metadata = challenge.metadata ?? const {};
      final verifier = metadata['verifier'];
      final nonce = metadata['nonce'];
      final redirectTo = metadata['redirectTo'];
      final isAdmin = metadata['isAdmin'] == true;
      final inviteToken = metadata['inviteToken'];
      if (verifier is! String || nonce is! String) {
        throw const InvalidOrExpiredCodeException(codeType: 'OAuth state');
      }

      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'resolve_provider';
      final provider = await _resolveOAuthProvider(table, providerId);
      logger.trace('resolve_provider');

      final appConfig = await getConfig();
      final redirectUri = _oauthRedirectUri(appConfig, providerId);

      step = 'exchange_code';
      final identity = await _exchangeCodeForIdentity(
        provider: provider,
        code: payload.code,
        redirectUri: redirectUri,
        codeVerifier: verifier,
        expectedNonce: nonce,
      );
      logger.trace('exchange_code');

      step = 'resolve_identity';
      final result = await _resolveOAuthSignIn(
        table: table,
        provider: provider,
        identity: identity,
        isAdmin: isAdmin,
        payload: payload,
        inviteToken: inviteToken is String ? inviteToken : null,
      );
      logger.trace('done');

      return (
        user: result.user,
        jwt: result.jwt,
        redirectTo: redirectTo is String ? redirectTo : null,
      );
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Ends a flow the provider rejected (RFC 6749 §4.1.2.1 `error=`), and
  /// returns the `redirect_to` recorded at start so the caller can send the
  /// browser back where it came from.
  ///
  /// The user pressing "Cancel" is a normal outcome, not a malformed request,
  /// but the destination still cannot be taken from the callback: it is read
  /// back out of *our own* challenge row, where [_startOAuth] put it only
  /// after [_isAllowedOAuthRedirect] approved it. Nothing the provider sends
  /// influences where this points (design §4 item 5).
  ///
  /// Consumes the challenge for the same reason the success path consumes it
  /// before exchanging: this `state` is spent either way, and leaving it
  /// consumable would keep a live challenge around for its full TTL after the
  /// flow it belonged to has ended.
  ///
  /// Returns `null` when no consumable challenge matches -- an unknown,
  /// expired or already-consumed `state`, all indistinguishable on purpose.
  /// The caller falls back to its own error handling rather than redirecting
  /// somewhere it cannot justify.
  Future<String?> _abandonOAuth(String state) async {
    final db = await open();
    final matches = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.secretHash.equals(_sha256Hex(state)) &
              authChallenges.type.equals(.oauthState) &
              authChallenges.canConsume.isTrue(),
        )
        .limit(1);

    final challenge = matches.singleOrNull;
    if (challenge == null) {
      return null;
    }

    await _consumeChallenge(challenge);

    final redirectTo = (challenge.metadata ?? const {})['redirectTo'];
    return redirectTo is String ? redirectTo : null;
  }

  // ---------------------------------------------------------------------
  // §3.2 — native / public-client flow.
  // ---------------------------------------------------------------------

  Future<_AuthResult> _nativeOAuth(
    String table,
    NativeOAuthAuthPayload payload, {
    bool isAdmin = false,
  }) async {
    logger.setTraceProps({
      'op': 'oauth_native',
      'table': table,
      'provider': payload.provider,
    });
    var step = 'start';
    logger.trace('start');
    try {
      step = 'table_access';
      await _requireAuthTableAccess(table, payload);
      logger.trace('table_access');

      step = 'resolve_provider';
      final provider = await _resolveOAuthProvider(table, payload.provider);
      logger.trace('resolve_provider');

      step = 'resolve_claims';
      final oauth_claims.OAuthIdentity identity;
      if (payload.idToken case final idToken?) {
        // The client's own SDK generated and consumed the nonce (§3.2:
        // "no challenge row, because the client owns the state") -- zonai
        // never minted one here to compare against, unlike the redirect
        // flow's callback. Signature/iss/aud/exp are still fully verified.
        identity = await _identityFromTokens(
          provider: provider,
          idToken: idToken,
          accessToken: null,
          expectedNonce: null,
        );
      } else if (payload.code case final code?) {
        final codeVerifier = payload.codeVerifier;
        final redirectUri = payload.redirectUri;
        if (codeVerifier == null || redirectUri == null) {
          throw ArgumentError(
            'NativeOAuthAuthPayload.code requires codeVerifier and redirectUri',
          );
        }
        identity = await _exchangeCodeForIdentity(
          provider: provider,
          code: code,
          redirectUri: redirectUri,
          codeVerifier: codeVerifier,
          expectedNonce: null,
        );
      } else {
        throw ArgumentError(
          'NativeOAuthAuthPayload requires either idToken or code',
        );
      }
      logger.trace('resolve_claims');

      step = 'resolve_identity';
      final result = await _resolveOAuthSignIn(
        table: table,
        provider: provider,
        identity: identity,
        isAdmin: isAdmin,
        payload: payload,
      );
      logger.trace('done');

      return (user: result.user, jwt: result.jwt);
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // §3.3 — identity resolution, linking, provisioning.
  // ---------------------------------------------------------------------

  Future<_AuthResult> _resolveOAuthSignIn({
    required String table,
    required OAuthProvider provider,
    required oauth_claims.OAuthIdentity identity,
    required bool isAdmin,
    required AuthPayload payload,
    String? inviteToken,
  }) async {
    final db = await open();

    // 1. (table, provider, subject) hit -> sign in. Done.
    final existingMatches = await db
        .select()
        .from(oauthIdentities)
        .where(
          oauthIdentities.table.equals(table) &
              oauthIdentities.provider.equals(provider.id) &
              oauthIdentities.subject.equals(identity.subject),
        )
        .limit(1);
    final existing = existingMatches.singleOrNull;

    if (existing != null) {
      final user = await _externalAuthUserById(
        table: table,
        id: existing.userId.value,
      );
      if (user == null) {
        throw UserNotFoundAuthException(table: table);
      }

      await db
          .update(oauthIdentities)
          .set(
            oauthIdentities.lastLoginAt.to(clock.now()),
            identity.email == null
                ? null
                : oauthIdentities.email.to(identity.email),
          )
          .where(oauthIdentities.id.equals(existing.id));

      await _requireAuthRecordAccess(table, .signIn, payload);
      return await _finishOAuthSignIn(
        table: table,
        user: user,
        isFirstSeen: false,
      );
    }

    // 2. Miss, provider asserts a matching email -> link, governed by
    // OAuthLinking (design §3.3, §4 item 6): `byVerifiedEmail` only links
    // when the provider marks the email verified; `never` never links;
    // `always` links on an unverified email too -- documented footgun.
    final canLinkByEmail = switch (provider.linking) {
      OAuthLinking.never => false,
      OAuthLinking.byVerifiedEmail =>
        identity.email != null && identity.emailVerified == true,
      OAuthLinking.always => identity.email != null,
    };

    if (canLinkByEmail) {
      final email = identity.email!;
      final user = await _authRecord(table: table, email: email);
      if (user != null) {
        final idColumn = await _dispatchOperation<ColumnNameResponse>(
          GetColumnNameRequest(table: table, columnName: .id),
        );
        final userId = user[idColumn.name];
        if (userId is! String) {
          throw UserNotFoundAuthException(table: table);
        }

        await db.insert(into: oauthIdentities).values([
          OAuthIdentity(
            id: OAuthIdentityId.generate(),
            table: table,
            userId: UnknownId(userId),
            provider: provider.id,
            subject: identity.subject,
            email: email,
          ),
        ]);

        await _requireAuthRecordAccess(table, .signIn, payload);
        return await _finishOAuthSignIn(
          table: table,
          user: user,
          isFirstSeen: false,
        );
      }
    }

    // 3. Still nothing -> provision. Admin sign-in never auto-provisions,
    // same rule password/OTP/magic-link admin flows enforce -- unless an
    // accepted admin invite authorizes it for this exact email (design
    // §3.2): the one place isAdmin provisioning is allowed.
    if (isAdmin) {
      if (inviteToken != null) {
        return await _provisionInvitedAdmin(
          table: table,
          provider: provider,
          identity: identity,
          inviteToken: inviteToken,
        );
      }
      throw UserNotFoundAuthException(table: table);
    }

    await _requireAuthRecordAccess(table, .signUp, payload);
    return await _provisionOAuthUser(
      table: table,
      provider: provider,
      identity: identity,
    );
  }

  /// Provisions a first-seen OAuth identity through the *same*
  /// `onExternalAuthFirstSeen` hook and `externalIdpProvisioningGate`
  /// [_provisionExternalAuthUser] (`external_idp.dart`) uses -- one
  /// provisioning story for the developer, regardless of which auth path
  /// triggered it. Claims carry a `sub`, matching the convention the
  /// extension is already expected to follow (insert the new row's `id` as
  /// `claims['sub']`) so [_externalAuthUserById] can find it afterward.
  Future<_AuthResult> _provisionOAuthUser({
    required String table,
    required OAuthProvider provider,
    required oauth_claims.OAuthIdentity identity,
  }) async {
    final issuer = provider.endpoints.issuer ?? 'oauth:${provider.id}';
    final allowed = await externalIdpProvisioningGate.canProvision(
      table: table,
      issuer: issuer,
      sub: identity.subject,
    );
    if (!allowed) {
      throw ExternalIdpProvisioningRejectedException(table: table);
    }

    final claims = <String, Object?>{
      'sub': identity.subject,
      if (identity.email != null) 'email': identity.email,
      if (identity.emailVerified != null)
        'email_verified': identity.emailVerified,
      if (identity.name != null) 'name': identity.name,
      if (identity.picture != null) 'picture': identity.picture,
    };

    await _runExtension(
      AuthExtensionRequest.onExternalAuthFirstSeen(
        table: table,
        object: claims,
        jwt: ProvisioningJwt(authTable: table),
      ),
    );
    await _executeEffects();

    final user = await _externalAuthUserById(
      table: table,
      id: identity.subject,
    );
    if (user == null) {
      throw UserNotFoundAuthException(table: table);
    }

    final db = await open();
    await db.insert(into: oauthIdentities).values([
      OAuthIdentity(
        id: OAuthIdentityId.generate(),
        table: table,
        userId: UnknownId(identity.subject),
        provider: provider.id,
        subject: identity.subject,
        email: identity.email,
      ),
    ]);

    return await _finishOAuthSignIn(
      table: table,
      user: user,
      isFirstSeen: true,
    );
  }

  /// Mints the session via the *same* [_createJwt] every other auth method
  /// uses (design §3.4). [isFirstSeen] skips `onSignIn` -- provisioning
  /// already ran `onExternalAuthFirstSeen` for this event, so firing
  /// `onSignIn` too would double-report one sign-in as two hooks.
  Future<_AuthResult> _finishOAuthSignIn({
    required String table,
    required Map<String, Object?> user,
    required bool isFirstSeen,
  }) async {
    final (jwt, token) = await _createJwt(table, user);

    if (!isFirstSeen) {
      await _runExtension(
        AuthExtensionRequest.onSignIn(table: table, object: user, jwt: jwt),
      );
    }

    await _executeEffects();
    return (user: user, jwt: token);
  }

  /// Design §3.2 steps 4-5: the one place an `isAdmin` OAuth callback is
  /// allowed to provision. Re-validates the invite against the database at
  /// callback time (not the snapshot [ZonaiDb.startAdminInviteOAuth] saw) so
  /// a revoke or expiry that happened mid-flow still lands (design §4 item
  /// 5). Consumption only happens on the match branch below -- a mismatch
  /// throws before either [_provisionOAuthUser] or [_consumeChallenge] run,
  /// so it creates nothing and leaves the invite usable (design §4 item 3).
  Future<_AuthResult> _provisionInvitedAdmin({
    required String table,
    required OAuthProvider provider,
    required oauth_claims.OAuthIdentity identity,
    required String inviteToken,
  }) async {
    final invite = await _findLiveAdminInvite(token: inviteToken, table: table);
    if (invite == null) {
      throw const InvalidOrExpiredCodeException(codeType: 'admin invite');
    }
    if (invite.expiresAt.isBefore(clock.now())) {
      throw const CodeExpiredException(codeType: 'admin invite');
    }

    final email = identity.email;
    if (email == null ||
        identity.emailVerified != true ||
        email.toLowerCase() != invite.target) {
      throw const AdminInviteEmailMismatchException();
    }

    final result = await _provisionOAuthUser(
      table: table,
      provider: provider,
      identity: identity,
    );

    await _consumeChallenge(invite);

    return result;
  }

  /// Looks up a live `adminInvite` challenge by its raw [token] -- the same
  /// exact-hash-match pattern used for `oauthState` above (design §2:
  /// `secretHash: sha256(token)`). Callers still check
  /// [AuthChallenge.expiresAt] themselves; `canConsume` alone doesn't rule
  /// out an expired-but-not-yet-swept row.
  Future<AuthChallenge?> _findLiveAdminInvite({
    required String token,
    required String table,
  }) async {
    final db = await open();
    final matches = await db
        .select()
        .from(authChallenges)
        .where(
          authChallenges.secretHash.equals(_sha256Hex(token)) &
              authChallenges.type.equals(.adminInvite) &
              authChallenges.table.equals(table) &
              authChallenges.canConsume.isTrue(),
        )
        .limit(1);
    return matches.singleOrNull;
  }

  // ---------------------------------------------------------------------
  // Provider config / token exchange / claim extraction.
  // ---------------------------------------------------------------------

  Future<OAuthProvider> _resolveOAuthProvider(
    String table,
    String providerId,
  ) async {
    final response = await _dispatchOperation<OAuthProviderConfigResponse>(
      GetOAuthProviderConfigRequest(table: table, providerId: providerId),
    );
    final provider = response.provider;
    if (provider == null) {
      throw OAuthProviderNotFoundException(table: table, provider: providerId);
    }
    return provider;
  }

  Future<oauth_claims.OAuthIdentity> _exchangeCodeForIdentity({
    required OAuthProvider provider,
    required String code,
    required String redirectUri,
    required String codeVerifier,
    required String? expectedNonce,
  }) async {
    final tokenClient = OAuthTokenExchangeClient(
      appleClientSecretSigner: _appleClientSecretSigner,
    );
    final tokens = await tokenClient.exchangeCode(
      provider: provider,
      code: code,
      redirectUri: redirectUri,
      // PKCE `code_verifier` never leaves this process on the redirect
      // flow -- it lived only in the hashed challenge's metadata and is
      // used here, server-side, for the exchange call itself (design §4
      // item 2). Omitted entirely for providers that don't use PKCE
      // (Apple, Facebook): sending an unexpected `code_verifier` to a
      // provider that never issued a `code_challenge` is just noise.
      codeVerifier: provider.usesPkce ? codeVerifier : null,
    );

    return await _identityFromTokens(
      provider: provider,
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
      expectedNonce: expectedNonce,
    );
  }

  Future<oauth_claims.OAuthIdentity> _identityFromTokens({
    required OAuthProvider provider,
    required String? idToken,
    required String? accessToken,
    required String? expectedNonce,
  }) async {
    final Map<String, Object?> claims;
    if (idToken != null) {
      claims = await _verifyOAuthIdTokenClaims(
        provider,
        idToken,
        expectedNonce: expectedNonce,
      );
    } else if (accessToken != null) {
      claims = await oauthUserInfoClient.fetch(
        provider: provider,
        accessToken: accessToken,
      );
    } else {
      throw const OAuthIdentityUnresolvedException(
        'no id_token or access_token to resolve identity from',
      );
    }

    var identity = oauth_claims.extractOAuthIdentity(provider.claims, claims);

    // GitHub's `GET /user` can return `email: null` for a private primary
    // address -- fall back to the verified primary from `/user/emails`
    // (design §2.3 / §3.3) rather than treating the sign-in as emailless.
    if (accessToken != null &&
        identity.email == null &&
        provider is BuiltInOAuthProvider &&
        provider.kind == OAuthProviderKind.github) {
      final email = await githubEmailResolver.primaryVerifiedEmail(accessToken);
      if (email != null) {
        identity = oauth_claims.OAuthIdentity(
          subject: identity.subject,
          email: email,
          emailVerified: true,
          name: identity.name,
          picture: identity.picture,
        );
      }
    }

    return identity;
  }

  /// Verifies signature/`iss`/`aud`/`exp` via [_jwksVerifierFor] (shared
  /// cache with `external_idp.dart`, keyed by JWKS URL) and, when
  /// [expectedNonce] is non-null, the `nonce` claim too (design §4 item 3 --
  /// every OIDC `id_token` the redirect flow issues a nonce for).
  Future<Map<String, Object?>> _verifyOAuthIdTokenClaims(
    OAuthProvider provider,
    String idToken, {
    required String? expectedNonce,
  }) async {
    final jwksConfig = oauthJwksConfig(provider);
    if (jwksConfig == null) {
      throw const OAuthIdentityUnresolvedException(
        'provider has no issuer/jwks to verify an id_token against',
      );
    }
    final verifier = _jwksVerifierFor(jwksConfig);
    if (expectedNonce == null) {
      return await verifier.verify(idToken);
    }
    return await verifyOAuthIdToken(
      verifier: verifier,
      idToken: idToken,
      expectedNonce: expectedNonce,
    );
  }

  // ---------------------------------------------------------------------
  // redirect_uri / redirect_to.
  // ---------------------------------------------------------------------

  /// Always derived from [AppConfig.baseUrl], never taken from the request
  /// (design §4 item 4) -- exact-matched against what was registered with
  /// the provider.
  String _oauthRedirectUri(AppConfig appConfig, String providerId) {
    final base = appConfig.baseUrl.endsWith('/')
        ? appConfig.baseUrl.substring(0, appConfig.baseUrl.length - 1)
        : appConfig.baseUrl;
    return '$base/auth/oauth/callback/$providerId';
  }

  /// `redirect_to` must be a relative path or an allowlisted origin (design
  /// §4 item 5) -- today the only allowlisted origin is the app's own
  /// [AppConfig.baseUrl], since there is no separate multi-origin config
  /// surface. A relative path is only accepted when it cannot be
  /// browser-resolved as protocol-relative: `//evil.com` and the
  /// backslash variant `/\evil.com` (some browsers normalize `\` to `/`)
  /// are both rejected even though they start with a single `/`.
  bool _isAllowedOAuthRedirect(String redirectTo, AppConfig appConfig) {
    if (redirectTo.startsWith('/') &&
        !redirectTo.startsWith('//') &&
        !redirectTo.startsWith(r'/\')) {
      return true;
    }

    final target = Uri.tryParse(redirectTo);
    final base = Uri.tryParse(appConfig.baseUrl);
    if (target == null || base == null) return false;
    if (!target.hasScheme || !target.hasAuthority) return false;

    return target.scheme == base.scheme &&
        target.host == base.host &&
        target.port == base.port;
  }

  String _sha256Hex(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
