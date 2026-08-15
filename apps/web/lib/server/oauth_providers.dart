import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';
import 'package:zonai_schema/payloads.dart';

/// Loads the redacted [OAuthProviderPublic] list from Zonai operations during SSR.
///
/// Sibling of `loadSupportedAuthTypes` in `supported_auth_types.dart` — same
/// scope set, same "the worker is not up yet, render an empty list rather than
/// a 500" fallback. `OAuthProvider.toPublic` is the redaction gate on the
/// other side of this call, so nothing reaching the dashboard carries a client
/// secret or a token endpoint (design §2.4).
///
/// Answers for **every** `OAuth`-enabled table, not just the `AsAdmin` one:
/// that is what `ZonaiDb.oauthProviders` exposes. See `oauthProvidersProvider`
/// consumers for how the sign-in screen uses the list.
Future<List<OAuthProviderPublic>> loadOAuthProviders() {
  return runMergedScopedFuture(
    () async {
      try {
        return await zonaiDB.oauthProviders();
      } on ExecutableUnavailableException {
        return const [];
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
