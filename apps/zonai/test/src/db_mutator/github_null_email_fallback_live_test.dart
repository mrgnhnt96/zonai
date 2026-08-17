@Tags(['live'])
library;

import 'dart:io';

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// The GitHub null-email fallback against **the real GitHub API**.
///
/// `github_null_email_fallback_test.dart` proves the branch fires and rebuilds
/// the identity, with the network faked. It cannot prove the thing that
/// actually breaks in production: that the shape it fakes is the shape GitHub
/// sends. This file is the other half — no stub, no fake client, the real
/// `OAuthUserInfoClient` and `GitHubEmailResolver` talking to
/// `api.github.com`.
///
/// **Tagged `live` and excluded from the default suite** (`dart_test.yaml`),
/// because it needs a credential and a network. Run it deliberately:
///
///     cd apps/zonai && dart test --tags live
///
/// Skipped loudly when `GITHUB_TOKEN` is absent, never silently passed — a
/// green tick from a test that did not run is worse than a red one, which is
/// the lesson `scripts.yaml`'s `test docs` target already records about
/// `apps/docs`' anchors test.
///
/// ## Why a PAT stands in for an OAuth access token
///
/// The two endpoints this path touches — `GET /user` and `GET /user/emails` —
/// accept either kind of bearer token and answer identically. What the PAT
/// cannot stand in for is the authorization leg: no consent screen, no code
/// exchange, no `state`. So this proves the identity-resolution half of a
/// GitHub sign-in, which is exactly the half that was faked, and claims
/// nothing about the redirect flow.
///
/// ## What it asserts, and what it must never print
///
/// The account under test has a **private primary email**, which is GitHub's
/// default — that is what makes it a real instance of the case rather than a
/// contrived one. The assertions are about shape: an email was resolved, it is
/// marked verified, and the subject survived GitHub's integer `id`. The
/// address itself is a real personal one and is never printed, never put in a
/// failure message, and never written anywhere.
void main() {
  group('GitHub null-email fallback (live)', () {
    final token = Platform.environment['GITHUB_TOKEN'];

    setUpAll(() {
      if (token == null || token.isEmpty) {
        markTestSkipped(
          'GITHUB_TOKEN is not set -- this test talks to api.github.com and '
          'is skipped rather than faked. Run with a token whose scopes '
          'include user:email.',
        );
      }
    });

    ZonaiDb newDb() {
      // The real collaborators: no httpClient argument anywhere below, which
      // is the point of the file.
      return runScoped(
        ZonaiDb.new,
        values: {
          settingsProvider.overrideWith(() => fakeSettings),
          fsProvider.overrideWith(LocalFileSystem.new),
          cleanUpProvider,
          executableStopProvider,
        },
      );
    }

    test(
      'resolves a real private primary address through GET /user/emails',
      () async {
        if (token == null || token.isEmpty) return;

        final db = newDb();
        final github = OAuthProvider.github(
          // Never sent: `GET /user` and `/user/emails` authorize on the bearer
          // token alone. Present because the factory requires them, and the
          // provider is what carries the `kind` the fallback is gated on.
          clientId: 'unused-for-userinfo',
          clientSecret: 'unused-for-userinfo',
        );

        final identity = await db.resolveIdentityFromTokens(
          provider: github,
          accessToken: token,
        );

        // The fallback ran. `GET /user` returned `email: null` for this account
        // (private primary), so anything non-null here came from
        // `GET /user/emails` -- there is no other source in this path.
        expect(
          identity.email,
          isNotNull,
          reason:
              'GET /user returns email:null for a private primary, so a null '
              'here means the fallback did not run against real GitHub',
        );
        expect(identity.email, contains('@'));

        // The half that would silently break linking: `/user/emails` only
        // yields an address it reports as verified, so the identity must say so
        // -- `OAuthLinking.byVerifiedEmail` refuses to link on anything else.
        expect(identity.emailVerified, isTrue);

        // GitHub's `id` is a JSON integer, not a string. A strict-string
        // subject extractor breaks every GitHub sign-in, and this is the
        // assertion that would have caught it against the real payload.
        expect(identity.subject, isNotEmpty);
        expect(int.tryParse(identity.subject), isNotNull);

        // Nothing above printed the address, and nothing below may either.
        // `identity.toString()` is not asserted on for that reason.
      },
    );
  });
}
