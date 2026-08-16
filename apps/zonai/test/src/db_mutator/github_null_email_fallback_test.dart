import 'dart:convert';

import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/utils/oauth/github_email_resolver.dart';
import 'package:zonai/src/utils/oauth/oauth_userinfo_client.dart';
import 'package:zonai_schema/zonai_schema.dart';

// `fakeSettings` rather than a second copy of it. `ZonaiDb`'s constructor
// eagerly builds a MailmanPool per worker kind and each reads `settings` as
// it is constructed, so even a db that never opens anything needs a scope for
// the moment of construction -- that file explains it at length and there is
// no reason for two answers to the same question to drift apart.
import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// The GitHub private-primary-email fallback (`docs/oauth.md` item 3).
///
/// `GET /user` returns `email: null` whenever the account's primary address is
/// private — GitHub's own default — and the runtime falls back to
/// `GET /user/emails` for the primary verified one. Until this file existed
/// the *branch* had no coverage at all: `github_email_resolver_test.dart`
/// covers the resolver in isolation, but the resolver was constructed inline
/// at the call site, so nothing could prove the branch fires, or that it
/// rebuilds the identity with `emailVerified: true`.
///
/// **Faked at the transport, not at the class.** Both collaborators are
/// `final class`, so neither can be subclassed from here — which is the better
/// outcome: injecting an `http.Client` leaves the real parsing, the real
/// Facebook `fields=` special-case and the real primary/verified selection in
/// the path under test, and fakes only the network.
///
/// The companion `github_null_email_fallback_live_test.dart` answers the one
/// question this file cannot: whether the response shape faked here is the
/// shape GitHub actually sends.
void main() {
  group('GitHub null-email fallback', () {
    /// `GET /user` as GitHub really answers it for a private primary address:
    /// an **integer** `id`, and a null `email`. The integer matters — a
    /// strict-string subject extractor breaks every GitHub sign-in, which is
    /// a bug this campaign already hit once.
    http.Client userInfoReturning(Object? email) {
      return MockClient((req) async {
        expect(req.url.toString(), 'https://api.github.com/user');
        return http.Response(
          jsonEncode({
            'id': 39742020,
            'email': email,
            'name': 'Octocat',
            'avatar_url': 'https://example.invalid/a.png',
          }),
          200,
        );
      });
    }

    http.Client emailsReturning(List<Map<String, Object?>> entries) {
      return MockClient((req) async {
        expect(req.url.toString(), 'https://api.github.com/user/emails');
        return http.Response(jsonEncode(entries), 200);
      });
    }

    /// Constructs a real [ZonaiDb] with both OAuth collaborators substituted.
    /// Nothing here opens a database — `resolveIdentityFromTokens` only
    /// touches the two clients and the provider — but the constructor still
    /// needs the scope, so it runs inside one.
    ZonaiDb dbWith({
      required http.Client userInfo,
      required http.Client emails,
    }) {
      return runScoped(
        () =>
            ZonaiDb()
              ..oauthUserInfoClient = OAuthUserInfoClient(httpClient: userInfo)
              ..githubEmailResolver = GitHubEmailResolver(httpClient: emails),
        values: {
          settingsProvider.overrideWith(() => fakeSettings),
          fsProvider.overrideWith(LocalFileSystem.new),
          cleanUpProvider,
          executableStopProvider,
        },
      );
    }

    final github = OAuthProvider.github(
      clientId: 'client-id',
      clientSecret: 'client-secret',
    );

    test('a null email is replaced by the primary verified address, and the '
        'identity says that address is verified', () async {
      final db = dbWith(
        userInfo: userInfoReturning(null),
        emails: emailsReturning(const [
          {'email': 'secondary@example.com', 'primary': false, 'verified': true},
          {'email': 'primary@example.com', 'primary': true, 'verified': true},
        ]),
      );

      final identity = await db.resolveIdentityFromTokens(
        provider: github,
        accessToken: 'gho_abc',
      );

      expect(identity.email, 'primary@example.com');
      // The half that would be easy to drop: the fallback address comes from
      // `/user/emails`, which only returns it as `verified: true`, so the
      // identity has to SAY it is verified. `OAuthLinking.byVerifiedEmail`
      // refuses to link on anything else, so a fallback that left this false
      // would resolve the email and then silently fail to link it.
      expect(identity.emailVerified, isTrue);
      expect(identity.subject, '39742020');
    });

    test('an account with no usable primary keeps a null email rather than '
        'inventing one', () async {
      final db = dbWith(
        userInfo: userInfoReturning(null),
        emails: emailsReturning(const [
          // Primary but unverified: the exact pair the resolver must refuse,
          // since treating it as verified would let an unverified address
          // link to an existing account.
          {'email': 'unverified@example.com', 'primary': true, 'verified': false},
        ]),
      );

      final identity = await db.resolveIdentityFromTokens(
        provider: github,
        accessToken: 'gho_abc',
      );

      expect(identity.email, isNull);
      expect(identity.emailVerified, isNot(isTrue));
    });

    test('a public email is used as-is and /user/emails is never called',
        () async {
      final db = dbWith(
        userInfo: userInfoReturning('public@example.com'),
        // Fails the test if the fallback fires when it should not: the branch
        // is guarded on `identity.email == null`, and a fallback that ran
        // anyway would spend a second API call on every GitHub sign-in.
        emails: MockClient((req) async {
          fail('/user/emails must not be called when GET /user has an email');
        }),
      );

      final identity = await db.resolveIdentityFromTokens(
        provider: github,
        accessToken: 'gho_abc',
      );

      expect(identity.email, 'public@example.com');
    });

    test('the fallback is GitHub-only -- another provider with a null email '
        'does not reach it', () async {
      // The branch is gated on `provider.kind == github` as well as on the
      // null email. Without this, a provider that legitimately returns no
      // email would have its identity resolved against GitHub's API using
      // that provider's access token.
      final gitlab = OAuthProvider.gitlab(
        clientId: 'client-id',
        clientSecret: 'client-secret',
      );

      final db = dbWith(
        userInfo: MockClient((req) async {
          // `sub`, not `id`: GitLab's OIDC userinfo names the subject the
          // OIDC way, and its claim map says so. Getting this wrong fails
          // with "subject path did not resolve", which is worth knowing is a
          // per-provider claim-map question rather than a shared one.
          return http.Response(
            jsonEncode({'sub': '7', 'email': null, 'name': 'Someone'}),
            200,
          );
        }),
        emails: MockClient((req) async {
          fail('the GitHub fallback must not run for a non-GitHub provider');
        }),
      );

      final identity = await db.resolveIdentityFromTokens(
        provider: gitlab,
        accessToken: 'glpat_abc',
      );

      expect(identity.email, isNull);
    });
  });
}
