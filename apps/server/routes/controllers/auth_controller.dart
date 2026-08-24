// ! All `authorization` headers MUST have the same parameter name "authorization" so
// that we can properly inject the token into the request on the client side
import 'dart:io' show HttpHeaders, HttpStatus;

import 'package:revali_router/revali_router.dart';
import 'package:revali_swagger_annotations/revali_swagger_annotations.dart'
    as swagger;
import 'package:zonai_server/src/exceptions/oauth_http_exception.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'package:zonai_web/utils/zonai_cookie.dart';

import '../components/auth_header_rate_limit.dart';
import '../components/black_list.dart';
import '../components/body_rate_limit.dart';
import '../components/oauth_rate_limit.dart';

// TODO: Tighten up the return types so that we don't need to dynamically access
// the `accessToken` key

// ! Spell the rate-limit operation out as `RateLimitOperation.x`, never as the
// dot-shorthand `.x` -- revali's server generator cannot resolve a dot-shorthand
// annotation argument. See docs/revali-dot-shorthand-codegen.md.

@BlackList()
@Controller('auth')
class AuthController {
  const AuthController({required this.authHandler});

  final AuthHandler authHandler;

  // The one structured error body zonai emits -- every other auth failure on
  // these routes is a bare `{"error": "<sentence>"}`. Documented on all three
  // password doors because all three run `_signInWithPassword`, which is what
  // raises it. See docs/auth.md, "Forced password reset".
  @swagger.ApiResponse(
    403,
    description:
        'The credentials were correct, but the account owes a new '
        'password before it may sign in. Body is the structured envelope '
        '`{"error": {"code": "password_reset_required", "message": ..., '
        '"details": {"resetToken": ..., "expiresIn": <seconds>, '
        '"reason": ...}}}`. Complete it with `POST /auth/confirm` carrying '
        '`resetToken`, then sign in again.',
  )
  @BodyRateLimit<AuthBody>(RateLimitOperation.authenticate)
  @Post()
  Future<Map<String, Object?>?> authenticate({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required AuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.authenticate(
      body,
      authorization: authorization,
    );
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @AuthHeaderRateLimit(RateLimitOperation.refreshToken)
  @Post('refresh')
  Future<Map<String, Object?>?> refreshToken({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.refreshToken(authorization);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @BodyRateLimit<ResetPasswordAuthBody>(RateLimitOperation.sendResetPassword)
  @Post('reset-password')
  Future<void> sendResetPassword({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required ResetPasswordAuthBody body,
  }) async {
    await authHandler.sendResetPassword(
      authorization: authorization,
      body: body,
    );
  }

  @BodyRateLimit<VerifyEmailAuthBody>(RateLimitOperation.sendVerifyEmail)
  @Post('verify-email')
  Future<void> sendVerifyEmail({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
    @Body() VerifyEmailAuthBody? body,
  }) async {
    await authHandler.sendVerifyEmail(authorization: authorization, body: body);
  }

  @Post('confirm')
  Future<Map<String, Object?>?> confirm({
    @Body() required VerifyAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.verifyAuth(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  // Without this guard the admin auth endpoint was exempt from ALL rate
  // limiting: `RateLimit.canContinue` learned to bucket admin bodies, but
  // nothing invoked it here, so online credential guessing against the most
  // privileged accounts was unlimited. `RateLimitOperation.adminAuthenticate`
  // resolves to the (tight) `adminAuthenticatePolicy`, bucketed per-IP on the
  // synthetic `__admin_auth__` key since admin auth carries no collection.
  // The one structured error body zonai emits -- every other auth failure on
  // these routes is a bare `{"error": "<sentence>"}`. Documented on all three
  // password doors because all three run `_signInWithPassword`, which is what
  // raises it. See docs/auth.md, "Forced password reset".
  @swagger.ApiResponse(
    403,
    description:
        'The credentials were correct, but the account owes a new '
        'password before it may sign in. Body is the structured envelope '
        '`{"error": {"code": "password_reset_required", "message": ..., '
        '"details": {"resetToken": ..., "expiresIn": <seconds>, '
        '"reason": ...}}}`. Complete it with `POST /auth/confirm` carrying '
        '`resetToken`, then sign in again.',
  )
  @BodyRateLimit<AdminAuthBody>(RateLimitOperation.adminAuthenticate)
  @Post('admin')
  Future<Map<String, Object?>?> adminAuthenticate({
    @Body() required AdminAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.adminAuthenticate(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  // The one structured error body zonai emits -- every other auth failure on
  // these routes is a bare `{"error": "<sentence>"}`. Documented on all three
  // password doors because all three run `_signInWithPassword`, which is what
  // raises it. See docs/auth.md, "Forced password reset".
  @swagger.ApiResponse(
    403,
    description:
        'The credentials were correct, but the account owes a new '
        'password before it may sign in. Body is the structured envelope '
        '`{"error": {"code": "password_reset_required", "message": ..., '
        '"details": {"resetToken": ..., "expiresIn": <seconds>, '
        '"reason": ...}}}`. Complete it with `POST /auth/confirm` carrying '
        '`resetToken`, then sign in again.',
  )
  @BodyRateLimit<SignInAuthBody>(RateLimitOperation.signIn)
  @Post('sign-in')
  Future<Map<String, Object?>> signIn({
    @Body() required SignInAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.signIn(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @BodyRateLimit<SignUpAuthBody>(RateLimitOperation.signUp)
  @Post('sign-up')
  Future<Map<String, Object?>> signUp({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required SignUpAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.signUp(authorization, body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // OAuth (docs/oauth-design.md §3). Path parameters are `:provider` in the
  // route string plus `@Param() required String provider` in the signature --
  // the same shape `PhotosController.view` (`@Get(':id')`) and
  // `DbController.custom` (`@Patch('custom/:operation')`) already serve on,
  // confirmed against `.revali/server/routes/__img_route.dart` rather than
  // assumed.
  //
  // The three redirect-flow routes return `Future<void>` and write the 302
  // through the injected `Response`. A non-void return would have revali's
  // generated handler assign `context.response.body = {'data': result}`
  // after the method ran, which is the one thing a redirect must not carry.
  // -----------------------------------------------------------------------

  /// The public, redacted provider list (design §2.4).
  ///
  /// `table` is an optional *filter*, not a required argument: the dashboard
  /// sign-in screen lists every `OAuth`-enabled collection at once, and a
  /// single-collection consumer passes `?table=`. Nothing here is
  /// authenticated because nothing here is a secret -- `toPublic()` is the
  /// redaction gate, asserted by `zonai_schema`'s own tests.
  @Get('oauth/providers')
  Future<List<Map<String, Object?>>> oauthProviders({
    @Query('table') String? table,
  }) async {
    return await authHandler.oauthProviders(table: table);
  }

  /// §3.1 step 1: mint the `oauthState` challenge, 302 to the provider.
  ///
  // The 302 is written at runtime through `Response`, so revali's generated
  // spec would otherwise advertise the default 200. These are documentation
  // only -- `@StatusCode` would ALSO emit `context.response..statusCode = n`
  // into the generated handler, which is a second, static writer of the one
  // thing these routes set dynamically.
  @swagger.ApiResponse(
    302,
    description:
        "Redirect to the provider's "
        'authorization endpoint. Carries `state` and `code_challenge` in the '
        'Location header.',
  )
  @swagger.ApiResponse(
    400,
    description:
        '`redirect_to` is neither a relative '
        "path nor this app's own origin",
  )
  @swagger.ApiResponse(404, description: 'No such provider on that table')
  @swagger.ApiResponse(429, description: 'oauthStart rate limit exceeded')
  @OAuthStartRateLimit()
  @Get('oauth/start/:provider')
  Future<void> startOAuth({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String provider,
    @Query('table') required String table,
    @Query('redirect_to') String? redirectTo,
    required Response response,
  }) async {
    final url = await authHandler.startOAuth(
      table: table,
      provider: provider,
      redirectTo: redirectTo,
      authorization: authorization,
    );

    // The authorization URL carries `state` and `code_challenge`, so it is
    // itself sensitive -- it goes in the `Location` header and nowhere else.
    // Notably not into the response body, which an error page or a proxy log
    // would then hold a copy of.
    _redirect(response, url);
  }

  /// §3.1 step 1 for the admin dashboard: mint an **admin** challenge, 302 to
  /// the provider.
  ///
  /// The `admin` path segment mirrors `@Post('admin')` above, and the reason
  /// it exists is the same one: the collection is resolved server-side rather
  /// than taken from the caller. [startOAuth] mints `isAdmin: false`, whose
  /// callback auto-provisions a first-seen identity — and on a collection
  /// that mixes in `AsAdmin` that provisioned row *is* an admin, because
  /// `JwtConfig.isAdmin` comes from the mixin with no per-row predicate. See
  /// [AuthHandler.startAdminOAuth].
  ///
  /// There is deliberately **no** admin callback route. The `isAdmin` flag
  /// rides the `oauthState` challenge's metadata and is read back out by
  /// `_completeOAuthCallback`, so the existing callback already distinguishes
  /// an admin flow. A second callback route would be a second `redirect_uri`
  /// to register with every provider, for no behavioural difference.
  @swagger.ApiResponse(
    302,
    description:
        "Redirect to the provider's "
        'authorization endpoint. Carries `state` and `code_challenge` in the '
        'Location header.',
  )
  @swagger.ApiResponse(
    400,
    description:
        '`redirect_to` is neither a relative '
        "path nor this app's own origin",
  )
  @swagger.ApiResponse(
    404,
    description:
        'No admin collection is configured for OAuth sign-in, or it '
        'has no such provider',
  )
  @swagger.ApiResponse(429, description: 'oauthStart rate limit exceeded')
  @OAuthAdminStartRateLimit()
  @Get('admin/oauth/start/:provider')
  Future<void> startAdminOAuth({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String provider,
    @Query('redirect_to') String? redirectTo,
    required Response response,
  }) async {
    final url = await authHandler.startAdminOAuth(
      provider: provider,
      redirectTo: redirectTo,
      authorization: authorization,
    );

    _redirect(response, url);
  }

  /// Is this invite link still good? Answered **without consuming it**
  /// (`docs/admin-invite-design.md` §7).
  ///
  /// The `/_/admin/invite?token=…` screen asks this before it offers
  /// anything, so a link opened a week too late gets that screen's own plain
  /// explanation. Without it the only thing that can judge a token is
  /// [startAdminInviteOAuth] below, and by the time that answers the browser
  /// has left the SPA — so a stale invite's first impression is a raw 401
  /// error page, on the one flow whose entire job is welcoming someone.
  ///
  /// Unauthenticated for the same reason [startAdminInviteOAuth] is: the
  /// invitee has no session, and the token is the authorization. It carries
  /// [OAuthInviteStartRateLimit] rather than a limit of its own — a new
  /// `RateLimitOperation` value would be a breaking change to the worker
  /// protocol (`min_schema_version.dart`), and sharing the invite-acceptance
  /// bucket with the start route it precedes is the right grouping anyway:
  /// the two are one visit.
  ///
  /// **200 either way, and the same body for every unusable token.** Not a
  /// 404 for "no such invite" and a 200 for "expired" — that difference is
  /// an oracle for which addresses have invites pending. The single answer
  /// is [AuthHandler.kAdminInviteUnusableBody]; the reason it is a constant
  /// there rather than a literal here is that a literal is how the two
  /// branches drift apart.
  ///
  /// `token` is redacted in the request log by `redactSensitiveQuery`, which
  /// already covers that parameter name — the same coverage
  /// [startAdminInviteOAuth] relies on, pinned by
  /// `trace_query_redaction_test.dart`.
  @swagger.ApiResponse(
    200,
    description:
        '`{live: true, table, authTypes}` when the token names an invite '
        'that can still be accepted, and `{live: false}` for every token '
        'that cannot -- expired, revoked, already accepted or unknown '
        'alike, deliberately indistinguishable. Never the invited email.',
  )
  @swagger.ApiResponse(429, description: 'oauthInviteStart rate limit exceeded')
  @OAuthInviteStartRateLimit()
  @Get('admin/invite')
  Future<Map<String, Object?>> adminInviteStatus({
    @Query('token') required String token,
  }) async {
    return await authHandler.adminInviteStatus(token: token);
  }

  /// Admin-invite acceptance over OAuth: mint an **invite-bound** challenge,
  /// 302 to the provider (`docs/admin-invite-design.md` §3.2 step 3).
  ///
  /// The browser reaches this from the `/_/admin/invite?token=…` screen the
  /// invite email links to, so it is a `GET` that redirects, exactly like the
  /// two start routes above — and unauthenticated, because the invitee has no
  /// session yet. `token` is the authorization.
  ///
  /// There is no matching callback route, for the same reason
  /// [startAdminOAuth] has none: the invite rides the `oauthState`
  /// challenge's metadata and `_completeOAuthCallback` reads it back out, so
  /// the existing `/auth/oauth/callback/:provider` already distinguishes this
  /// flow. A second callback would be a second `redirect_uri` to register with
  /// every provider for no behavioural difference.
  ///
  /// `token` in a query string is logged only as `token=<redacted>`:
  /// `redactSensitiveQuery` already covers that parameter name, and
  /// `Trace.wrap` runs it over every request line including 4xx ones. Pinned
  /// by `trace_query_redaction_test.dart`, not assumed.
  ///
  /// The OAuth half of acceptance. [acceptAdminInvite] below is design §3.3's
  /// other half, for admin tables that sign in with a password, an OTP or a
  /// magic link; the acceptance screen picks between them from the
  /// `authTypes` [adminInviteStatus] reports.
  @swagger.ApiResponse(
    302,
    description:
        "Redirect to the provider's "
        'authorization endpoint. Carries `state` and `code_challenge` in the '
        'Location header.',
  )
  @swagger.ApiResponse(
    400,
    description:
        '`redirect_to` is neither a relative '
        "path nor this app's own origin",
  )
  @swagger.ApiResponse(
    401,
    description: 'The invite token names no live invite, or it has expired',
  )
  @swagger.ApiResponse(
    404,
    description:
        'No admin collection is configured for OAuth sign-in, or it '
        'has no such provider',
  )
  @swagger.ApiResponse(429, description: 'oauthStart rate limit exceeded')
  @OAuthInviteStartRateLimit()
  @Get('admin/invite/oauth/start/:provider')
  Future<void> startAdminInviteOAuth({
    @Param() required String provider,
    @Query('token') required String token,
    @Query('redirect_to') String? redirectTo,
    required Response response,
  }) async {
    final url = await authHandler.startAdminInviteOAuth(
      provider: provider,
      inviteToken: token,
      redirectTo: redirectTo,
    );

    _redirect(response, url);
  }

  /// Design §3.3: accept an admin invite directly — create the row, consume
  /// the invite and sign in — on a table whose sign-in is a password, an OTP
  /// or a magic link rather than a provider.
  ///
  /// Unauthenticated, like the two routes above it and for the same reason:
  /// the invitee has no session, and the token is the authorization. Here
  /// that token is all the authorization there is, which is why the runtime
  /// refuses this route for a table declaring OAuth alone — there, a provider
  /// additionally vouches that the identity signing in owns the invited
  /// address, and this path cannot make that claim.
  ///
  /// A `POST`, not the `GET` its sibling is, because it creates an admin
  /// account. The token rides the **body** for the same reason: a query
  /// string reaches request logs, browser history and any `Referer` sent from
  /// the resulting page, and `redactSensitiveQuery` covering the parameter
  /// name is a mitigation for the routes that have no choice, not a licence
  /// to put a credential there when there is one.
  ///
  /// The response is the ordinary session payload with `X-Auth`, identical to
  /// `sign-in` — the invitee ends up signed in as the admin they just became.
  @swagger.ApiResponse(
    200,
    description:
        'Admin account created, invite consumed, session minted. Same body '
        'as `POST /auth/sign-in`, with the access token also in `X-Auth`.',
  )
  @swagger.ApiResponse(
    400,
    description:
        'The table requires a password and none was sent, or one was sent '
        'to a table that has no password sign-in',
  )
  @swagger.ApiResponse(
    401,
    description:
        'The token names no invite that can still be accepted -- expired, '
        'revoked, already accepted or unknown alike',
  )
  @swagger.ApiResponse(
    409,
    description:
        "The invite's admin table accepts invites through an OAuth provider "
        'only; use `GET admin/invite/oauth/start/:provider`',
  )
  @swagger.ApiResponse(429, description: 'oauthInviteStart rate limit exceeded')
  @OAuthInviteStartRateLimit()
  @Post('admin/invite/accept')
  Future<Map<String, Object?>> acceptAdminInvite({
    @Body() required AdminInviteAcceptBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.acceptAdminInvite(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  /// §3.1 step 2, the shape every provider except Apple sends: a `GET` with
  /// `code`/`state` (or `error`) in the query string.
  @swagger.ApiResponse(
    302,
    description:
        'Session minted; redirect to the '
        '`redirect_to` recorded at start',
  )
  @swagger.ApiResponse(
    400,
    description:
        'Provider returned `error`, or the '
        'callback carried no usable `code`/`state`',
  )
  @swagger.ApiResponse(401, description: 'Unknown, replayed or expired `state`')
  @swagger.ApiResponse(429, description: 'oauthCallback rate limit exceeded')
  @OAuthCallbackRateLimit()
  @Get('oauth/callback/:provider')
  Future<void> oauthCallback({
    @Param() required String provider,
    @Query('code') String? code,
    @Query('state') String? state,
    @Query('error') String? error,
    required Response response,
  }) async {
    await _completeOAuth(
      authHandler,
      response,
      provider: provider,
      code: code,
      state: state,
      error: error,
    );
  }

  /// §3.1 step 2 over `form_post`.
  ///
  /// Sign in with Apple posts the callback as
  /// `application/x-www-form-urlencoded` instead of redirecting with a query
  /// string whenever `name` or `email` scope was requested -- and `name email`
  /// is `OAuthProvider.apple`'s own default. Identical handling, different
  /// transport; see [OAuthCallbackBody].
  ///
  // The generated spec declares this body as `application/json` because that
  // is revali_swagger's only request-body content type and there is no
  // annotation to widen it. The runtime is not so narrow: revali's payload
  // resolver switches on the request's actual mime type
  // (`payload_impl.dart`'s `resolve`), and
  // `application/x-www-form-urlencoded` resolves to the same map shape
  // `OAuthCallbackBody.fromJson` reads. The spec is narrower than the route,
  // not wrong about it.
  @swagger.ApiResponse(
    302,
    description:
        'Session minted; redirect to the '
        '`redirect_to` recorded at start',
  )
  @swagger.ApiResponse(
    400,
    description:
        'Provider returned `error`, or the '
        'callback carried no usable `code`/`state`',
  )
  @swagger.ApiResponse(401, description: 'Unknown, replayed or expired `state`')
  @swagger.ApiResponse(429, description: 'oauthCallback rate limit exceeded')
  @OAuthCallbackRateLimit()
  @Post('oauth/callback/:provider')
  Future<void> oauthCallbackFormPost({
    @Param() required String provider,
    @Body() required OAuthCallbackBody body,
    required Response response,
  }) async {
    await _completeOAuth(
      authHandler,
      response,
      provider: provider,
      code: body.code,
      state: body.state,
      error: body.error,
    );
  }

  /// §3.2, the native / public-client flow. Returns `{accessToken, user}` and
  /// sets `X-Auth` exactly like every other session-minting route above.
  @BodyRateLimit<OAuthBody>(RateLimitOperation.authenticate)
  @Post('oauth')
  Future<Map<String, Object?>> oauth({
    @Body() required OAuthBody body,
    required ResponseHeaders headers,
  }) async {
    final result = await authHandler.oauthNative(body);
    if (result case {'accessToken': final String accessToken}) {
      headers.add('X-Auth', accessToken);
    }
    return result;
  }

  @Delete()
  Future<void> logout({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
  }) async {
    await authHandler.logout(authorization);
  }

  @Delete('all')
  Future<void> logoutAll({
    @Header(HttpHeaders.authorizationHeader) required String authorization,
  }) async {
    await authHandler.logoutAll(authorization);
  }
}

// ! Everything below is a TOP-LEVEL function, not a private method on
// AuthController. Revali's generator walks a @Controller's methods to build
// routes; a helper sitting among them is one refactor away from someone
// giving it an annotation, and it would read as a route in the generated
// output before anyone noticed. Nothing outside a @Controller class is
// scanned, so out here it cannot become one by accident.

/// Where a callback lands when the flow carried no `redirect_to`.
///
/// Root rather than the dashboard's `/_` mount: this server also fronts
/// non-dashboard apps, and sending an app's users into the admin UI because
/// they omitted a parameter is a worse default than sending them home.
const _kDefaultOAuthRedirect = '/';

Future<void> _completeOAuth(
  AuthHandler authHandler,
  Response response, {
  required String provider,
  required String? code,
  required String? state,
  required String? error,
}) async {
  final ({Map<String, Object?> user, String jwt, String? redirectTo}) result;
  try {
    result = await authHandler.completeOAuth(
      provider: provider,
      code: code,
      state: state,
      error: error,
    );
  } on OAuthProviderRejectedException catch (rejected) {
    // A provider `error=` is usually the user pressing Cancel, which is a
    // normal outcome mid-browser-redirect rather than a client error. The
    // 400 this used to answer unconditionally is a dead end for a browser:
    // the dashboard's own callback screen already renders human copy for
    // `access_denied` and never got the chance to.
    //
    // Only redirect to a destination the *start* recorded and
    // `_isAllowedOAuthRedirect` already approved -- so this cannot become an
    // open redirect via a forged `state`. With no such destination there is
    // nowhere defensible to send anyone, and the 400 stands.
    if (rejected.redirectTo case final target?) {
      _redirectWithError(response, target, rejected.error);
      return;
    }
    rethrow;
  }

  _redirect(
    response,
    result.redirectTo ?? _kDefaultOAuthRedirect,
    accessToken: result.jwt,
  );
}

/// 302s to [location] carrying the provider's short error *code* as `?error=`.
///
/// The code only -- never `error_description`, which is provider-controlled
/// free text (design §4 item 7, and the same stance `OAuthProviderRejected
/// Exception` takes). It goes through [Uri]'s query encoding rather than
/// string concatenation, so a provider cannot smuggle extra parameters into a
/// URL we assembled.
///
/// No session is handed over: nothing was minted, and there is nothing to
/// hand.
void _redirectWithError(Response response, String location, String error) {
  final target = Uri.parse(location);
  final withError = target.replace(
    queryParameters: {...target.queryParameters, 'error': error},
  );

  _redirect(response, withError.toString());
}

/// Writes a 302 to [location], optionally handing the freshly minted session
/// to the browser on the way.
///
/// [accessToken] goes into two places and neither of them is the URL. A token
/// in a `Location` query string is written to every proxy log, browser
/// history entry and `Referer` header between here and the destination.
///
/// - `X-Auth`, matching every other session-minting route on this controller.
///   A browser following the redirect cannot read it; a programmatic client
///   that follows redirects itself can, and so can a test.
/// - the `zonai_auth_token` cookie, whose attributes are copied from
///   `CookieStorage.write` so a session minted here is indistinguishable from
///   one the dashboard wrote itself after a password sign-in (design §3.1
///   step 2). Not `HttpOnly`, deliberately and documented on [ZonaiCookie]:
///   the dashboard's own client reads it back to attach to API calls.
void _redirect(Response response, String location, {String? accessToken}) {
  response.statusCode = HttpStatus.found;
  response.headers.add(HttpHeaders.locationHeader, location);

  if (accessToken == null) return;

  response.headers.add('X-Auth', accessToken);
  response.headers.add(
    HttpHeaders.setCookieHeader,
    '${ZonaiCookie.authToken.key}=${Uri.encodeComponent(accessToken)}; '
    'Path=/; Max-Age=${ZonaiCookie.authToken.maxAge.inSeconds}; SameSite=Lax',
  );
}
