import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';

/// Result of validating the auth cookie during SSR.
final class SsrSession {
  const SsrSession({required this.signedIn, required this.clearAuthCookie});

  final bool signedIn;

  /// True when the cookie should be expired on the response (invalid/revoked JWT).
  final bool clearAuthCookie;
}

/// Whether SSR should mount [HomeAppShell] for this request.
///
/// When JWT verification is inconclusive but a non-stale cookie is present,
/// prefer the signed-in shell so post-login navigation is not bounced back to
/// sign-in. The client still validates the token on API calls.
bool ssrShowsSignedInShell(SsrSession session, String? token) {
  if (session.signedIn) {
    return true;
  }
  return token != null && token.isNotEmpty && !session.clearAuthCookie;
}

/// Validates [token] for SSR and decides whether to clear a stale cookie.
Future<SsrSession> resolveSsrSession(String? token) {
  return runMergedScopedFuture(
    () async {
      if (token == null || token.isEmpty) {
        return const SsrSession(signedIn: false, clearAuthCookie: false);
      }

      try {
        final jwt = await zonaiDB.parseJwt(token);
        return SsrSession(signedIn: jwt != null, clearAuthCookie: false);
      } on InvalidJwtException {
        return const SsrSession(signedIn: false, clearAuthCookie: true);
      } on JwtRecordNotFoundException {
        return const SsrSession(signedIn: false, clearAuthCookie: true);
      } on ExecutableUnavailableException {
        return await _resolveFromClaimsOnly(token);
      } on AuthException {
        return const SsrSession(signedIn: false, clearAuthCookie: true);
      } catch (_) {
        return await _resolveFromClaimsOnly(token);
      }
    },
    includeIfAbsent: {
      argsProvider,
      cleanUpProvider,
      configProvider,
      configResolverProvider,
      extensionsProvider,
      executableStopProvider,
      processProvider,
      loggerProvider,
      fsProvider,
      operationsProvider,
      rulesProvider,
      rateLimitsProvider,
      settingsProvider.overrideWith(() {
        if (kIsCompiled) {
          return Settings.load();
        }
        return Settings.load(fs.path.join('..', 'playground'));
      }),
      zonaiDbProvider,
    },
  );
}

Future<SsrSession> _resolveFromClaimsOnly(String token) async {
  try {
    final jwt = await zonaiDB.parseJwtClaimsOnly(token);
    return SsrSession(signedIn: jwt != null, clearAuthCookie: false);
  } on InvalidJwtException {
    return const SsrSession(signedIn: false, clearAuthCookie: true);
  } on AuthException {
    return const SsrSession(signedIn: false, clearAuthCookie: true);
  } catch (_) {
    return const SsrSession(signedIn: false, clearAuthCookie: false);
  }
}

/// Returns true when [token] verifies and still has a row in `_jwt`.
Future<bool> isStoredAuthTokenValid(String? token) async {
  final session = await resolveSsrSession(token);
  return session.signedIn;
}
