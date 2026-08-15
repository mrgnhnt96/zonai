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
/// Narrowed to the `AsAdmin` collection's own providers.
///
/// `ZonaiDb.oauthProviders` answers for **every** `OAuth`-enabled table, which
/// is right for a general consumer and wrong for this one: these tiles begin
/// an *admin* sign-in via `/auth/admin/oauth/start/:provider`, a route that
/// resolves the admin collection itself and therefore cannot serve a provider
/// declared only on an app table. Listing one would render a button whose
/// only outcome is a 404.
///
/// The `StateError` arm is the schema that declares no admin OAuth collection
/// at all (`_adminCollectionFor`'s "no oauth sign-in is configured for
/// admin"). Same stance as the [ExecutableUnavailableException] arm: an empty
/// list, which `OAuthProviderButtons` already explains to the developer,
/// rather than a 500 on the sign-in page.
Future<List<OAuthProviderPublic>> loadOAuthProviders() {
  return runMergedScopedFuture(
    () async {
      try {
        final adminTable = await zonaiDB.adminOAuthTable();
        final providers = await zonaiDB.oauthProviders();
        return [
          for (final provider in providers)
            if (provider.table == adminTable) provider,
        ];
      } on ExecutableUnavailableException {
        return const [];
      } on StateError {
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
