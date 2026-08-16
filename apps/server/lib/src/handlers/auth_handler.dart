import 'package:zonai/zonai.dart';
// `AdminInviteDescription`, the record `ZonaiDb.describeAdminInvite` answers
// with. `deps/zonai_db.dart` imports the library without re-exporting it, so
// the name is not in scope from that import alone.
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_server/src/exceptions/oauth_http_exception.dart';

class AuthHandler {
  const AuthHandler();

  Future<Map<String, Object?>?> adminAuthenticate(AdminAuthBody body) async {
    if (body case final AuthBody body) {
      return authenticate(body);
    }

    throw ArgumentError(
      'Unexpected body type, needs to be a $AuthBody, got ${body.runtimeType}',
    );
  }

  Future<Map<String, Object?>?> refreshToken(String authorization) async {
    final token = switch (authorization) {
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };

    final result = await zonaiDB.refreshToken(token);

    if (result == null) {
      throw StateError('Failed to refresh token');
    }

    return _sessionPayload(result.user, result.jwt);
  }

  Future<Map<String, Object?>?> authenticate(
    AuthBody body, {
    String? authorization,
  }) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };

    final payload = switch (body) {
      SignInAuthBody() => SignInPasswordAuthPayload(
        email: body.email,
        password: body.password,
      ),
      SignUpAuthBody() => SignUpPasswordAuthPayload(
        email: body.email,
        password: body.password,
        object: body.object,
      ),
      SendOtpAuthBody() => SendOtpAuthPayload(
        email: body.email,
        object: body.metadata,
        jwt: token,
      ),
      SendMagicLinkAuthBody() => SendMagicLinkAuthPayload(
        email: body.email,
        object: body.metadata,
      ),
    };

    final result = switch (body) {
      AdminAuthBody() => await zonaiDB.authenticateAdmin(payload),
      _ => await zonaiDB.authenticate(body.table, payload),
    };

    return switch ((body, result)) {
      (SignInAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (SignUpAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (SendOtpAuthBody(), null) => null,
      (VerifyOtpAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (SendMagicLinkAuthBody(), null) => null,
      (VerifyMagicLinkAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      _ => throw UnimplementedError('Unknown auth body: $body'),
    };
  }

  Future<Map<String, Object?>?> verifyAuth(VerifyAuthBody body) async {
    final VerifyAuthPayload payload = switch (body) {
      VerifyOtpAuthBody() => VerifyOtpAuthPayload(
        email: body.email,
        code: body.code,
      ),
      VerifyMagicLinkAuthBody() => VerifyMagicLinkAuthPayload(
        secret: body.secret,
      ),
      ConfirmResetPasswordAuthBody() => ConfirmResetPasswordAuthPayload(
        token: body.token,
        newPassword: body.newPassword,
      ),
      ConfirmVerifyEmailAuthBody() => VerifyEmailAuthPayload(token: body.token),
    };

    final result = await zonaiDB.confirmAuth(payload);

    return switch ((body, result)) {
      (VerifyOtpAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (VerifyMagicLinkAuthBody(), final result?) => _sessionPayload(
        result.user,
        result.jwt,
      ),
      (ConfirmResetPasswordAuthBody(), null) => null,
      (ConfirmVerifyEmailAuthBody(), null) => null,
      _ => throw UnimplementedError('Unknown verify auth body: $body'),
    };
  }

  Future<Map<String, Object?>> signIn(SignInAuthBody body) async {
    final result = await zonaiDB.authenticate(
      body.table,
      SignInPasswordAuthPayload(email: body.email, password: body.password),
    );
    return _sessionPayload(result!.user, result.jwt);
  }

  Future<Map<String, Object?>> signUp(
    String? authorization,
    SignUpAuthBody body,
  ) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };
    final result = await zonaiDB.authenticate(
      body.table,
      SignUpPasswordAuthPayload(
        email: body.email,
        password: body.password,
        object: body.object,
        jwt: token,
      ),
    );
    return _sessionPayload(result!.user, result.jwt);
  }

  Future<void> logout(String authorizationHeader) async {
    final token = _parseBearerAuthorization(authorizationHeader);
    await zonaiDB.logout(token);
  }

  Future<void> logoutAll(String authorizationHeader) async {
    final token = _parseBearerAuthorization(authorizationHeader);
    await zonaiDB.logoutAll(token);
  }

  Future<void> sendResetPassword({
    required ResetPasswordAuthBody body,
    String? authorization,
  }) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };
    final payload = ResetPasswordAuthPayload(email: body.email, jwt: token);

    switch (body) {
      case AdminSendResetPasswordAuthBody():
        await zonaiDB.sendAdminResetPassword(payload);
      case SendResetPasswordAuthBody():
        await zonaiDB.sendResetPassword(body.table, payload);
    }
  }

  Future<void> sendVerifyEmail({
    required String authorization,
    VerifyEmailAuthBody? body,
  }) async {
    final token = _parseBearerAuthorization(authorization);
    zonaiDB.sendVerifyEmailAuthenticated(token, switch (body) {
      VerifyEmailAuthBody() => SendVerifyEmailAuthPayload(
        email: body.email,
        table: body.table,
      ),
      null => null,
    });
  }

  // ---------------------------------------------------------------------
  // OAuth (docs/oauth-design.md §3). Every method here is a thin adapter
  // over `zonaiDB`'s OAuth entry points -- the flows themselves live in
  // `parts/auth/oauth.dart`, and nothing below re-implements any of them.
  // ---------------------------------------------------------------------

  /// Every `(table, provider)` pair the schema declares, redacted by
  /// `OAuthProvider.toPublic` (design §2.4), optionally narrowed to one
  /// [table].
  ///
  /// Filtering here rather than at the operation: `ZonaiDb.oauthProviders`
  /// answers for every `OAuth`-enabled table at once, which is what the
  /// dashboard's sign-in screen wants, and `?table=` is the single-collection
  /// view of the same list.
  Future<List<Map<String, Object?>>> oauthProviders({String? table}) async {
    return filterOAuthProviders(await zonaiDB.oauthProviders(), table);
  }

  /// §3.1 step 1. Returns the provider's authorization URL to redirect to.
  Future<String> startOAuth({
    required String table,
    required String provider,
    String? redirectTo,
    String? authorization,
  }) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };

    return await zonaiDB.startOAuth(
      table,
      StartOAuthAuthPayload(
        provider: provider,
        redirectTo: redirectTo,
        jwt: token,
      ),
    );
  }

  /// §3.1 step 1 for the **admin dashboard**, and the reason it is a separate
  /// entry point rather than [startOAuth] with a `table`.
  ///
  /// [startOAuth] takes the collection from the caller and mints a challenge
  /// flagged `isAdmin: false`, so its callback reaches
  /// `_resolveOAuthSignIn`'s provisioning branch. Point that at a collection
  /// that mixes in `AsAdmin` and the flow *creates* a row there — and
  /// `JwtConfig.isAdmin` is derived from the mixin alone
  /// (`db_operations.dart`'s `_getJwtConfig`: `isAdmin: admin != null`), with
  /// no per-row predicate, so the row it just created signs in as a full
  /// admin. `AuthRowRules.canSignUp` does not stop it either: its `.oauth`
  /// arm is `schema is OAuth`, which an `AsAdmin` table satisfies.
  ///
  /// So this resolves the admin collection server-side — the caller cannot
  /// name it — and `ZonaiDb.startAdminOAuth` flags the challenge
  /// `isAdmin: true`, which the callback reads back out of the challenge
  /// metadata and refuses to provision under. Same rule
  /// [adminAuthenticate] and `sendAdminResetPassword` already enforce for
  /// password, OTP and magic-link admin sign-in.
  Future<String> startAdminOAuth({
    required String provider,
    String? redirectTo,
    String? authorization,
  }) async {
    final token = switch (authorization) {
      null => null,
      final String bearerToken => _parseBearerAuthorization(bearerToken),
    };

    return await zonaiDB.startAdminOAuth(
      StartOAuthAuthPayload(
        provider: provider,
        redirectTo: redirectTo,
        jwt: token,
      ),
    );
  }

  /// Admin-invite acceptance over OAuth (`docs/admin-invite-design.md` §3.2
  /// step 3), and [startAdminOAuth]'s counterpart for someone who is *not* an
  /// admin yet.
  ///
  /// Deliberately unauthenticated: the invitee has no session, and if they
  /// had an admin one they would not need an invite. [inviteToken] is the
  /// authorization, and `ZonaiDb.startAdminInviteOAuth` refuses up front when
  /// it names no live invite rather than deferring every failure to the
  /// callback.
  ///
  /// This is not [startAdminOAuth] with a token bolted on. That one mints a
  /// challenge whose callback refuses to provision an `isAdmin` row at all —
  /// correct for admin *sign-in*, and exactly wrong here, where creating the
  /// row is the point. The invite token rides the challenge metadata and is
  /// what lifts that refusal, for the invited address only (design §3.2
  /// step 4).
  /// The liveness probe behind `GET /auth/admin/invite?token=` (design §7).
  ///
  /// The body shape is decided here rather than in the controller because it
  /// is the *same* body for every unusable token, and that sameness is the
  /// security property — see [kAdminInviteUnusableBody]. A route that built
  /// its own answer per branch is exactly how the two cases drift apart.
  ///
  /// `{live: true, table, authTypes}` for an invite that can still be
  /// accepted; [kAdminInviteUnusableBody] for anything else. Never the
  /// invited email and never the token: the caller supplied the token, and
  /// the email is what a forged one must not be able to discover.
  Future<Map<String, Object?>> adminInviteStatus({
    required String token,
  }) async {
    return adminInviteStatusBody(await zonaiDB.describeAdminInvite(token: token));
  }

  /// The probe's answer as a function of the runtime's, split out from
  /// [adminInviteStatus] so the mapping is falsifiable without a database.
  ///
  /// The runtime already collapses expired, revoked, spent, forged and
  /// unknown into one `null` (`_describeAdminInvite` explains why). This is
  /// the other half of that guarantee: **one `null` in, one shared constant
  /// out**, so there is no branch here for a reason to be attached to.
  static Map<String, Object?> adminInviteStatusBody(
    AdminInviteDescription? invite,
  ) {
    if (invite == null) return kAdminInviteUnusableBody;

    return {
      'live': true,
      'table': invite.table,
      // Names, not indices: an `AuthType` gaining a value must not silently
      // renumber what an older dashboard reads.
      'authTypes': [for (final type in invite.authTypes) type.name],
    };
  }

  /// The one answer every unusable invite token gets.
  ///
  /// Expired, revoked, already accepted, forged, truncated — one body, one
  /// status, no reason attached. If "expired" and "no such invite" differed
  /// by so much as an error code, this route would be an oracle for which
  /// addresses have invites pending, which is the same thing
  /// `DELETE /admin/invites/:email` answers identically to avoid.
  ///
  /// A const so there is literally one object to return; a per-branch map
  /// literal is how a stray field gets added to one branch and not the other.
  static const kAdminInviteUnusableBody = <String, Object?>{'live': false};

  Future<String> startAdminInviteOAuth({
    required String provider,
    required String inviteToken,
    String? redirectTo,
  }) async {
    return await zonaiDB.startAdminInviteOAuth(
      inviteToken: inviteToken,
      payload: StartOAuthAuthPayload(
        provider: provider,
        redirectTo: redirectTo,
        // No caller session to carry. An invitee signing in from the invite
        // link has none, and `_startAdminInviteOAuth` authorizes on the
        // invite token instead.
        jwt: null,
      ),
    );
  }

  /// §3.1 step 2. Consumes the challenge, exchanges the code, resolves the
  /// identity and mints the session.
  ///
  /// [error] is the provider's own RFC 6749 §4.1.2.1 rejection (the user hit
  /// "cancel", the client is misconfigured). It arrives *instead of*
  /// [code]/[state] and is surfaced as a 400 carrying the error code —
  /// never [errorDescription] verbatim, which is provider-controlled text
  /// that would be reflected into our response body.
  Future<({Map<String, Object?> user, String jwt, String? redirectTo})>
  completeOAuth({
    required String provider,
    required String? code,
    required String? state,
    String? error,
  }) async {
    if (error != null && error.isNotEmpty) {
      // The user pressing "Cancel" is the common case here, and it is a
      // normal outcome rather than a client error. Recover the destination
      // the flow recorded at start so the route can send the browser back to
      // it; `abandonOAuth` also spends the challenge, which would otherwise
      // stay live for its full TTL after the flow it belonged to ended.
      //
      // A callback with no usable `state` leaves [redirectTo] null and the
      // route falls back to answering 400 -- there is no destination this
      // server can justify, and the provider does not get to supply one.
      final redirectTo = switch (state) {
        null => null,
        final String state when state.isEmpty => null,
        final String state => await zonaiDB.abandonOAuth(state),
      };

      throw OAuthProviderRejectedException(
        provider: provider,
        error: error,
        redirectTo: redirectTo,
      );
    }

    // A callback with neither an error nor a usable code/state pair is a
    // malformed request, not a failed sign-in: answer 400 rather than
    // letting a null cast surface as a 500.
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      throw OAuthCallbackIncompleteException(
        provider: provider,
        hasCode: code != null && code.isNotEmpty,
        hasState: state != null && state.isNotEmpty,
      );
    }

    final result = await zonaiDB.completeOAuth(
      CompleteOAuthAuthPayload(state: state, code: code),
    );

    return (user: result.user, jwt: result.jwt, redirectTo: result.redirectTo);
  }

  /// §3.2, the native / public-client flow. Routed through the same
  /// `zonaiDB.authenticate` every other sign-in uses — `NativeOAuthAuthPayload`
  /// is dispatched by `parts/auth/auth.dart`'s payload switch.
  Future<Map<String, Object?>> oauthNative(OAuthBody body) async {
    final result = await zonaiDB.authenticate(
      body.table,
      nativeOAuthPayloadFor(body),
    );
    if (result == null) {
      throw StateError('OAuth sign-in did not produce a session');
    }
    return _sessionPayload(result.user, result.jwt);
  }

  Map<String, Object?> _sessionPayload(
    Map<String, Object?> user,
    String accessToken,
  ) {
    return {'accessToken': accessToken, 'user': user};
  }

  String _parseBearerAuthorization(String authorizationHeader) {
    final trimmed = authorizationHeader.trim();
    if (trimmed.isEmpty) {
      throw StateError('Authorization header is required');
    }

    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      final token = trimmed.substring(prefix.length).trim();
      if (token.isEmpty) throw StateError('Bearer token is empty');
      return token;
    }

    return trimmed;
  }
}

// The two functions below are top-level and public on purpose. Everything
// else `AuthHandler` does is one call into `zonaiDB`, which cannot be
// constructed without the whole scoped-dep tree behind it (`settings`, `args`,
// `fs`, a Mailman pool per worker). These two carry the only decisions this
// file makes on its own, so they are lifted out where a test can reach them
// without standing up a database.

/// Narrows a `(table, provider)` list to one [table], or returns all of it
/// when [table] is null.
///
/// `null` means "every collection", not "no collections": `?table=` is an
/// optional filter on `GET /auth/oauth/providers`, and the dashboard's
/// sign-in screen omits it deliberately to list every `OAuth`-enabled table
/// at once.
List<Map<String, Object?>> filterOAuthProviders(
  List<OAuthProviderPublic> providers,
  String? table,
) {
  return [
    for (final provider in providers)
      if (table == null || provider.table == table) provider.toJson(),
  ];
}

/// Maps a `POST /auth/oauth` body onto the payload the db mutator dispatches
/// on (design §3.2).
///
/// The two shapes are not interchangeable and the switch is exhaustive over a
/// sealed type, so a third body shape added later cannot silently fall
/// through to one of these.
NativeOAuthAuthPayload nativeOAuthPayloadFor(OAuthBody body) {
  return switch (body) {
    OAuthIdTokenBody(:final provider, :final idToken) =>
      NativeOAuthAuthPayload.idToken(provider: provider, idToken: idToken),
    OAuthCodeBody(
      :final provider,
      :final code,
      :final codeVerifier,
      :final redirectUri,
    ) =>
      NativeOAuthAuthPayload.code(
        provider: provider,
        code: code,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      ),
  };
}
