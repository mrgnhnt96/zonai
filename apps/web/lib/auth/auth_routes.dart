import 'package:zonai_schema/payloads.dart';

/// URL paths for the web app.
abstract final class AuthRoutes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const tables = '/tables';
  static const maintenance = '/maintenance';

  /// The signed-in Admins screen: current admins and pending invites.
  static const admins = '/admins';

  /// Where the invite email's link lands (`{baseUrl}/_/admin/invite?token=…`,
  /// built in `invite_admin.dart`).
  ///
  /// Reached by someone with **no session at all** — that is the whole point
  /// of an invite — so it is an [isPublicAuthPath] and lives in [authRoutes],
  /// not [homeRoutes].
  static const adminInviteAccept = '/admin/invite';
  static const magicLinkCallback = '/auth/magic-link';
  static const resetPasswordCallback = '/auth/reset-password';
  static const resetPasswordRequest = '/auth/reset-password/request';
  static const verifyEmailCallback = '/auth/verify-email';

  /// Where the server's OAuth callback sends the browser back to.
  ///
  /// Distinct from the server's own `/auth/oauth/callback/:provider` route:
  /// this one lives under [mountPath] (`/_/auth/oauth/callback`), so the two
  /// never collide even though the tails match.
  static const oauthCallback = '/auth/oauth/callback';

  /// Base path for the web app and Jaspr asset URL stripping.
  static const mountPath = '/_';

  /// True when [path] is the mount itself or a page under it (e.g. `/_`, `/_/sign-in`).
  static bool isMountedWebPath(String path) {
    if (mountPath == '/' || mountPath.isEmpty) {
      return true;
    }
    return path == mountPath || path.startsWith('$mountPath/');
  }

  static String forType(AuthType type) => '$signIn/${type.name}';

  static String forTable(String sqliteName) => '$tables/${Uri.encodeComponent(sqliteName)}';

  static String? tableSqliteNameFromPath(String path) {
    final normalized = normalizePath(path);
    final prefix = '$tables/';
    if (!normalized.startsWith(prefix)) {
      return null;
    }

    final segment = normalized.substring(prefix.length);
    if (segment.isEmpty || segment.contains('/')) {
      return null;
    }

    return Uri.decodeComponent(segment);
  }

  static bool isSignInPath(String path) {
    final normalized = normalizePath(path);
    return normalized == signIn ||
        normalized.startsWith('$signIn/') ||
        normalized == magicLinkCallback ||
        normalized == resetPasswordCallback ||
        normalized == resetPasswordRequest ||
        normalized == verifyEmailCallback ||
        normalized == oauthCallback;
  }

  static bool isVerifyEmailCallbackPath(String path) {
    return normalizePath(path) == verifyEmailCallback;
  }

  static bool isAdminsPath(String path) {
    return normalizePath(path) == admins;
  }

  /// True for the invite acceptance page, with or without its `?token=`.
  ///
  /// [normalizePath] parses and keeps only the path, so the token never
  /// reaches this comparison — which is what lets every caller here treat the
  /// route as a plain constant and keeps the token out of everything derived
  /// from a path (page titles, redirect targets, back links).
  static bool isAdminInviteAcceptPath(String path) {
    return normalizePath(path) == adminInviteAccept;
  }

  /// Paths an unauthenticated visitor is allowed to stay on.
  ///
  /// [adminInviteAccept] is deliberately **not** in [isSignInPath]: that set
  /// is what `AuthNotifier` and `HomeRouter` bounce a *signed-in* user away
  /// from, and it drives [backPath]. Being public and being a sign-in page are
  /// two different things, and this route is only the first.
  static bool isPublicAuthPath(String path) {
    return isSignInPath(path) || isVerifyEmailCallbackPath(path) || isAdminInviteAcceptPath(path);
  }

  /// Auth pages a **signed-in** browser must be allowed to stay on.
  ///
  /// [isSignInPath] is what bounces a session-holder home, and for almost
  /// every member of that set it is right: there is nothing to do on a sign-in
  /// form you no longer need. These two are the exceptions, because each
  /// carries its own authority in the URL and that authority is *not* the
  /// session cookie — the `?s=` decodes to `secret:email` and names the
  /// account it acts on, which need not be the one already signed in.
  ///
  /// Deliberately excluded, each for its own reason:
  ///
  /// * [oauthCallback] — arriving here *with* a session is the success path;
  ///   the server minted the cookie on its own 302, so home is where this
  ///   visitor was going. See `OAuthCallbackScreen`.
  /// * [adminInviteAccept] — spent on this browser (see [isPublicAuthPath]).
  /// * [magicLinkCallback] — would mint a *second*, different session over the
  ///   first. Signing out before honouring it is the only correct answer and
  ///   this set does not attempt it.
  /// * [resetPasswordRequest] — asks for a link by email; a signed-in visitor
  ///   already has the account open.
  static bool isSignedInReachableAuthPath(String path) {
    return isResetPasswordCallbackPath(path) || isVerifyEmailCallbackPath(path);
  }

  static bool isMagicLinkCallbackPath(String path) {
    return normalizePath(path) == magicLinkCallback;
  }

  static bool isResetPasswordCallbackPath(String path) {
    return normalizePath(path) == resetPasswordCallback;
  }

  static bool isResetPasswordRequestPath(String path) {
    return normalizePath(path) == resetPasswordRequest;
  }

  static bool isOAuthCallbackPath(String path) {
    return normalizePath(path) == oauthCallback;
  }

  /// Full-page destination that begins [startPath]'s OAuth flow.
  ///
  /// [startPath] is [OAuthProviderPublic.startPath] — a *server* route
  /// (`/auth/oauth/start/:provider?table=`), deliberately outside [mountPath]:
  /// the browser leaves the dashboard SPA entirely, visits the provider, and
  /// only comes back once the server has minted the session. `redirect_to` is
  /// the mounted [oauthCallback] URL, a relative path, which is the shape the
  /// server's own open-redirect allowlist accepts (design §4 item 5).
  static String oauthStartUrl(String startPath) {
    final separator = startPath.contains('?') ? '&' : '?';
    return '$startPath${separator}redirect_to=${Uri.encodeQueryComponent(toUrlPath(oauthCallback))}';
  }

  /// Full-page destination that begins [providerId]'s **admin** OAuth flow.
  ///
  /// Built from the provider id rather than [OAuthProviderPublic.startPath],
  /// because that field is the *public* route
  /// (`/auth/oauth/start/:provider?table=`) and this dashboard is the admin
  /// sign-in. The public route mints a challenge flagged `isAdmin: false`,
  /// whose callback auto-provisions a first-seen identity — and the admin
  /// collection mixes in `AsAdmin`, so the row it would create signs in as a
  /// full admin. `/auth/admin/oauth/start/:provider` resolves that collection
  /// server-side and flags the challenge `isAdmin: true`, which is what makes
  /// the callback refuse to provision.
  ///
  /// Carries no `table`: naming one is exactly the capability the admin route
  /// withholds.
  static String oauthAdminStartUrl(String providerId) {
    return '/auth/admin/oauth/start/$providerId'
        '?redirect_to=${Uri.encodeQueryComponent(toUrlPath(oauthCallback))}';
  }

  /// Full-page destination that accepts an admin invite through [providerId]
  /// (`docs/admin-invite-design.md` §3.2 step 3).
  ///
  /// A third start route, and the distinction from [oauthAdminStartUrl] is the
  /// whole point: that one requires an admin Bearer token and refuses to
  /// provision, because a stranger arriving at an `AsAdmin` collection must
  /// not become an admin by signing in. This one is unauthenticated — the
  /// invitee has no session yet — and [inviteToken] *is* the authorization.
  /// The server checks the token names a live invite before it mints anything,
  /// then requires the provider's verified email to equal the invited address
  /// at callback.
  ///
  /// The token rides in the query string because that is where
  /// `GET /auth/admin/invite/oauth/start/:provider` reads it, and it is the
  /// only place this app ever puts it: not in the page title, not in a link's
  /// text, not in any state that outlives the navigation.
  static String oauthInviteStartUrl(String providerId, String inviteToken) {
    return '/auth/admin/invite/oauth/start/$providerId'
        '?token=${Uri.encodeQueryComponent(inviteToken)}'
        '&redirect_to=${Uri.encodeQueryComponent(toUrlPath(oauthCallback))}';
  }

  static bool isSignInRoot(String path) {
    final normalized = normalizePath(path);
    return normalized == home || normalized == signIn;
  }

  /// Destination for the auth back control, or `null` when back should be hidden.
  static String? backPath(String path, List<AuthType> authTypes) {
    if (isResetPasswordRequestPath(path)) {
      if (authTypes.contains(AuthType.password)) {
        return forType(AuthType.password);
      }
      return authTypes.length > 1 ? signIn : null;
    }

    if (isResetPasswordCallbackPath(path) ||
        isMagicLinkCallbackPath(path) ||
        isVerifyEmailCallbackPath(path) ||
        isOAuthCallbackPath(path)) {
      if (authTypes.length > 1) {
        return signIn;
      }
      if (authTypes.length == 1) {
        return forType(authTypes.single);
      }
      return signIn;
    }

    if (typeFromPath(path) != null && authTypes.length > 1) {
      return signIn;
    }

    return null;
  }

  static AuthType? typeFromPath(String path) {
    final normalized = _normalizePath(path);
    if (!normalized.startsWith('$signIn/')) {
      return null;
    }

    final segment = normalized.substring('$signIn/'.length);
    if (segment.isEmpty || segment.contains('/')) {
      return null;
    }

    return AuthType.values.where((type) => type.name == segment).firstOrNull;
  }

  static String normalizePath(String path) => _normalizePath(path);

  static String fromUrlPath(String url) => normalizePath(url);

  /// Redirects legacy mount-less browser URLs to [mountPath].
  static String? routerRedirectToMountedLocation(String location) {
    final uri = location.contains('://')
        ? Uri.parse(location)
        : Uri.parse('http://localhost${location.startsWith('/') ? location : '/$location'}');
    final mounted = toUrlPath(normalizePath(location));
    if (uri.path == mounted) {
      return null;
    }
    if (uri.hasQuery) {
      return '$mounted?${uri.query}';
    }
    return mounted;
  }

  /// Maps an app route (e.g. `/sign-in`) to its URL under [mountPath].
  static String toUrlPath(String path) {
    final normalized = normalizePath(path);
    if (mountPath == '/' || mountPath.isEmpty) {
      return normalized;
    }
    if (normalized == home) {
      return mountPath;
    }
    return '$mountPath$normalized';
  }

  /// Rewrites a jaspr_router location (often mount-less) to the public browser URL.
  static String toMountedBrowserLocation(String location) {
    final uri = location.contains('://')
        ? Uri.parse(location)
        : Uri.parse('http://localhost${location.startsWith('/') ? location : '/$location'}');
    final path = toUrlPath(normalizePath(uri.path));
    if (!uri.hasQuery) {
      return path;
    }
    return '$path?${uri.query}';
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) {
      return home;
    }

    final uri = path.contains('://') ? Uri.parse(path) : Uri.parse('http://localhost$path');
    var normalized = uri.path;
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    if (mountPath != '/' && mountPath.isNotEmpty) {
      if (normalized == mountPath) {
        return home;
      }
      final prefix = '$mountPath/';
      if (normalized.startsWith(prefix)) {
        normalized = normalized.substring(mountPath.length);
      }
    }

    return normalized;
  }
}
