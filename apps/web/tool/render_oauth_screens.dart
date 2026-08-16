// Renders the real dashboard sign-in screens to standalone HTML files so they
// can be screenshotted without the whole zonai stack.
//
// This is NOT a substitute for running the compiled binary: the provider list
// here is supplied directly rather than loaded from a live operations worker.
// Everything downstream of that list -- the app shell, the router, the sign-in
// screen, the provider buttons, the bundled brand marks and every style rule --
// is the real component tree that SSR renders in production, via the same
// `renderComponent` entry point `main.server.dart` uses.
//
//   dart run tool/render_oauth_screens.dart <output-dir>
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/app.dart';
import 'package:zonai_web/auth/oauth_providers_provider.dart';
import 'package:zonai_web/auth/supported_auth_types_provider.dart';
import 'package:zonai_web/components/oauth_sign_in_screen.dart';
import 'package:zonai_web/components/sign_in_screen.dart';
import 'package:zonai_web/components/theme/oauth_button.dart';
import 'package:zonai_web/components/theme/ui_styles.dart';
import 'package:zonai_web/constants/theme.dart' hide styles;
import 'package:zonai_web/constants/theme.dart' as theme show styles;
import 'package:zonai_web/providers/app_name_provider.dart';
import 'package:zonai_web/providers/brand_logo_provider.dart';

OAuthProviderPublic _provider(String id, String displayName, OAuthProviderKind kind) {
  return OAuthProviderPublic(
    id: id,
    displayName: displayName,
    table: 'users',
    kind: kind,
    startPath: '/auth/oauth/start/$id?table=users',
  );
}

/// Mirrors what `apps/playground` declares, plus a custom provider so the
/// letter-tile fallback for an unknown kind is visible too.
final _providers = [
  _provider('google', 'Google', OAuthProviderKind.google),
  _provider('github', 'GitHub', OAuthProviderKind.github),
  _provider('apple', 'Apple', OAuthProviderKind.apple),
  _provider('microsoft', 'Microsoft', OAuthProviderKind.microsoft),
  _provider('acme', 'Acme SSO', OAuthProviderKind.custom),
];

Future<void> _render({
  required String path,
  required List<AuthType> authTypes,
  required List<OAuthProviderPublic> providers,
  required String outPath,
}) async {
  final response = await renderComponent(
    Document(
      // Every stylesheet the real document pulls in, so the capture is styled
      // the way the dashboard actually is rather than as bare markup.
      styles: [...theme.styles, ...zonaiUiStyles, ...oauthButtonStyles, ...App.styles, ...OAuthProviderButtons.styles],
      head: [
        script(content: themeBootstrapScript),
        meta(name: 'viewport', content: 'width=device-width, initial-scale=1'),
      ],
      // The whole-App path renders only a client-island placeholder here --
      // AuthAppShell hydrates in the browser -- so pump the screen inside the
      // provider overrides SSR installs, exactly as apps/web's own component
      // tests do.
      body: ProviderScope(
        overrides: [
          supportedAuthTypesProvider.overrideWithValue(authTypes),
          oauthProvidersProvider.overrideWithValue(providers),
          appNameProvider.overrideWithValue('Banana'),
          hasBrandLogoProvider.overrideWithValue(false),
        ],
        child: div(classes: 'app-root', [const AuthTypePickerScreen()]),
      ),
    ),
  );
  // `path` only labels which case this is; the screen is pumped directly.
  assert(path.isNotEmpty);

  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(response.body);
  stdout.writeln('wrote $outPath (${response.body.length} bytes)');

  // The same render pinned to light mode. Worth capturing separately: the
  // GitHub and Apple marks are monochrome `currentcolor` and must invert,
  // which a dark-only screenshot cannot show.
  // utf8.decode, not String.fromCharCodes: the response is UTF-8 bytes, and
  // treating them as code units turns the theme toggle's ☾ into mojibake.
  final light = utf8.decode(response.body).replaceFirst('<html>', '<html data-theme="light">');
  final lightPath = outPath.replaceFirst('.html', '-light.html');
  await File(lightPath).writeAsString(light);
  stdout.writeln('wrote $lightPath');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/render_oauth_screens.dart <out-dir>');
    exitCode = 64;
    return;
  }
  final out = args.first;

  Jaspr.initializeApp(useIsolates: false);

  // Every method a project might declare, which is what the picker is for.
  await _render(
    path: '/sign-in',
    authTypes: const [AuthType.password, AuthType.otp, AuthType.magicLink, AuthType.oauth],
    providers: _providers,
    outPath: '$out/sign-in-all-methods.html',
  );

  // OAuth as the only way in -- the page must still be usable, with no
  // vestigial "choose a method" step for a single option.
  await _render(
    path: '/sign-in',
    authTypes: const [AuthType.oauth],
    providers: _providers,
    outPath: '$out/sign-in-oauth-only.html',
  );

  // Password + OAuth, the combination docs/oauth-design.md uses as its
  // worked example.
  await _render(
    path: '/sign-in',
    authTypes: const [AuthType.password, AuthType.oauth],
    providers: [_providers[0], _providers[1], _providers[2]],
    outPath: '$out/sign-in-password-and-oauth.html',
  );
}
