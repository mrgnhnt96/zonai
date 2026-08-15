// Bundled, hand-authored brand marks for every built-in OAuthProviderKind
// except OAuthProviderKind.custom.
//
// Every mark is built from Jaspr's typed svg/path/rect components — never
// from a raw SVG string — so there is nothing here for sanitizeInlineSvg
// (oauth_sanitize.dart) to apply to: this rung can't carry an injection
// because it never accepts caller-supplied markup.
//
// GitHub and Apple use `fill: Color.currentColor` instead of a fixed hex —
// that's the whole light/dark story for a monochrome mark. It inherits
// whatever `color` the ambient context sets: left alone, that's the
// `color: fgColor` rule on `html, body` in constants/theme.dart, which
// already flips with [data-theme]/prefers-color-scheme — so these marks
// invert for free. OAuthProviderButton overrides `color` to
// OAuthProviderPublic.foreground on its own colored background, and the
// same `currentColor` fill picks that up instead. No new CSS variable
// needed for either case.
//
// Every other mark is a multi-color or single fixed-hue official mark and
// is never recolored — each fill below is copied verbatim from the
// provider's own brand asset (source cited per mark).

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

Component oauthBrandMark(OAuthProviderKind kind, {required double size}) {
  final mark = switch (kind) {
    OAuthProviderKind.google => googleOAuthMark(),
    OAuthProviderKind.apple => appleOAuthMark(),
    OAuthProviderKind.github => githubOAuthMark(),
    OAuthProviderKind.microsoft => microsoftOAuthMark(),
    OAuthProviderKind.facebook => facebookOAuthMark(),
    OAuthProviderKind.discord => discordOAuthMark(),
    OAuthProviderKind.gitlab => gitlabOAuthMark(),
    OAuthProviderKind.linkedin => linkedinOAuthMark(),
    OAuthProviderKind.custom => throw ArgumentError.value(
      kind,
      'kind',
      'oauthBrandMark has no bundled mark for OAuthProviderKind.custom — '
          'resolve custom providers through OAuthProviderIcon instead.',
    ),
  };
  return div(classes: 'z-oauth-mark', styles: Styles(width: size.px, height: size.px), [mark]);
}

/// Google's 4-color "G" icon.
///
/// Source: `developers.google.com/static/identity/images/branding_guideline_sample_lt_sq_sl.svg`,
/// one of the pre-approved button-icon assets linked from Google's Sign in
/// with Google branding guidelines
/// (https://developers.google.com/identity/branding-guidelines), fetched
/// 2026-08-15. Path data and fills (`#4285F4`/`#34A853`/`#FBBC04`/`#E94235`)
/// are copied unmodified from that file.
Component googleOAuthMark() {
  return svg(viewBox: '10 10 20 20', width: 100.percent, height: 100.percent, [
    path(
      [],
      fill: const Color('#4285F4'),
      d:
          'M29.6 20.2273C29.6 19.5182 29.5364 18.8364 29.4182 18.1818H20V22.05H25.3818C25.15 23.3 24.4455 24.3591 '
          '23.3864 25.0682V27.5773H26.6182C28.5091 25.8364 29.6 23.2727 29.6 20.2273Z',
    ),
    path(
      [],
      fill: const Color('#34A853'),
      d:
          'M20 30C22.7 30 24.9636 29.1045 26.6181 27.5773L23.3863 25.0682C22.4909 25.6682 21.3454 26.0227 20 '
          '26.0227C17.3954 26.0227 15.1909 24.2636 14.4045 21.9H11.0636V24.4909C12.7091 27.7591 16.0909 30 20 30Z',
    ),
    path(
      [],
      fill: const Color('#FBBC04'),
      d:
          'M14.4045 21.9C14.2045 21.3 14.0909 20.6591 14.0909 20C14.0909 19.3409 14.2045 18.7 14.4045 18.1V15.5091H'
          '11.0636C10.3864 16.8591 10 18.3864 10 20C10 21.6136 10.3864 23.1409 11.0636 24.4909L14.4045 21.9Z',
    ),
    path(
      [],
      fill: const Color('#E94235'),
      d:
          'M20 13.9773C21.4681 13.9773 22.7863 14.4818 23.8227 15.4727L26.6909 12.6045C24.9591 10.9909 22.6954 10 '
          '20 10C16.0909 10 12.7091 12.2409 11.0636 15.5091L14.4045 18.1C15.1909 15.7364 17.3954 13.9773 20 13.9773Z',
    ),
  ]);
}

/// Apple's logo glyph. Monochrome — inverts via `currentColor` (see class
/// doc comment).
///
/// Source: `developer.apple.com/apple-logo.svg`, served directly from
/// Apple's own developer site (used as its mask/pinned-tab icon), fetched
/// 2026-08-15. Path data copied unmodified.
Component appleOAuthMark() {
  return svg(viewBox: '0 0 73 73', width: 100.percent, height: 100.percent, [
    path(
      [],
      fill: Color.currentColor,
      d:
          'M47.1055431,11.5129519 C49.8885194,8.51619449 51.4065065,4.29540934 51.1535087,0.0746241978 '
          'C47.3585409,0.0746241978 42.9310785,2.31164032 40.1902685,5.56164489 C37.9976205,8.30515523 '
          '35.6784735,12.5259404 36.5217997,16.7889334 C40.4432664,17.2532197 44.6598972,14.7629565 '
          '47.1055431,11.5129519 L47.1055431,11.5129519 Z M50.8161782,17.7175061 C44.912895,17.7175061 '
          '39.6842728,20.9675107 36.9434628,20.9675107 C33.9918212,20.9675107 29.7751904,17.5486747 '
          '25.0103975,17.7175061 C18.8119502,17.8441297 13.1194986,21.5162127 9.87269285,26.9188177 '
          'C7.68004482,30.7597322 6.79455234,35.2759723 6.83671865,39.918836 C6.92105127,48.6980691 '
          '10.3786885,57.8571728 14.4266541,63.7240642 C17.546961,68.1558886 21.0467645,72.9253758 '
          '26.0223889,72.9253758 C30.4920176,72.9253758 32.1786699,69.9286183 37.9976205,69.9286183 '
          'C43.4370742,69.9286183 45.1658929,72.9253758 49.8885194,72.9253758 C54.8219775,72.9253758 '
          '58.1109495,68.4091357 61.0625911,63.9351034 C64.7732262,58.7013299 65.9960492,53.7208034 '
          '66.1647144,53.551972 C65.9960492,53.551972 56.6351287,49.7532654 56.2977983,38.9058475 '
          'C56.2977983,29.409081 64.0142327,25.146088 64.3093968,24.9350487 C60.1349323,18.4350396 '
          '53.3461567,17.7175061 50.8161782,17.7175061 L50.8161782,17.7175061 Z',
    ),
  ]);
}

/// GitHub's Octicons "mark-github" glyph. Monochrome — inverts via
/// `currentColor` (see class doc comment).
///
/// Source: `github.com/primer/octicons` (`icons/mark-github-16.svg`),
/// GitHub's own MIT-licensed icon set, purpose-built for exactly this kind
/// of small monochrome UI glyph and used throughout GitHub's own product.
/// GitHub's brand page (`brand.github.com/foundations/logo`) confirms the
/// Invertocat "should only appear in white, black, or in a few cases grey or
/// green" but is a JS-rendered SPA with no fetchable raw asset — Octicons is
/// the traceable, GitHub-authored alternative. Fetched 2026-08-15.
Component githubOAuthMark() {
  return svg(viewBox: '0 0 16 16', width: 100.percent, height: 100.percent, [
    path(
      [],
      fill: Color.currentColor,
      d:
          'M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.'
          '625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 '
          '1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 '
          '3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 '
          '12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c'
          '-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.09'
          '3-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.26'
          '6-.265.47-.5.657-.656',
    ),
  ]);
}

/// Microsoft's four-square logo. Fixed colors — never inverts.
///
/// Source: `learn.microsoft.com/en-us/entra/identity-platform/media/howto-add-branding-in-apps/ms-symbollockup_mssymbol_19.svg`,
/// linked from Microsoft's identity-platform branding guidelines
/// (`learn.microsoft.com/en-us/entra/identity-platform/howto-add-branding-in-apps`),
/// fetched 2026-08-15. Grid and colors copied unmodified.
Component microsoftOAuthMark() {
  return svg(viewBox: '0 0 21 21', width: 100.percent, height: 100.percent, [
    rect(x: '1', y: '1', width: '9', height: '9', fill: const Color('#F25022'), []),
    rect(x: '1', y: '11', width: '9', height: '9', fill: const Color('#00A4EF'), []),
    rect(x: '11', y: '1', width: '9', height: '9', fill: const Color('#7FBA00'), []),
    rect(x: '11', y: '11', width: '9', height: '9', fill: const Color('#FFB900'), []),
  ]);
}

/// Facebook's circular "f" mark. Fixed colors — never inverts.
///
/// Source: viewBox and path data as served in the HTML/SVG markup of
/// facebook.com itself (`en.wikipedia.org/wiki/File:Facebook_f_logo_(2021).svg`
/// documents this provenance directly). Brand blue confirmed live from
/// Meta's own design-system token (`--fds-blue-60: #1877F2`) embedded in
/// `meta.com/brand/resources/facebookapp/logo`, fetched 2026-08-15 — used
/// here as a flat fill in place of that page's app-icon gradient, matching
/// Meta's own published rule that the only approved flat treatments are
/// "blue-on-white or white-on-blue".
Component facebookOAuthMark() {
  return svg(viewBox: '0 0 40 40', width: 100.percent, height: 100.percent, [
    path(
      fill: const Color('#1877F2'),
      d: 'M16.7,39.8C7.2,38.1,0,29.9,0,20C0,9,9,0,20,0s20,9,20,20c0,9.9-7.2,18.1-16.7,19.8l-1.1-0.9h-4.4L16.7,39.8z',
      [],
    ),
    path(
      [],
      fill: const Color('#FFFFFF'),
      d:
          'M27.8,25.6l0.9-5.6h-5.3v-3.9c0-1.6,0.6-2.8,3-2.8h2.6V8.2c-1.4-0.2-3-0.4-4.4-0.4c-4.6,0-7.8,2.8-7.8,7.8V20h-5'
          'v5.6h5v14.1c1.1,0.2,2.2,0.3,3.3,0.3c1.1,0,2.2-0.1,3.3-0.3V25.6H27.8z',
    ),
  ]);
}

/// Discord's "Clyde" symbol. Fixed color — never inverts.
///
/// Source: `discord.com/branding` official brand-asset download
/// (`Discord_Symbol_Color/Discord-Symbol-Blurple.svg`), fetched 2026-08-15.
/// Path data and Blurple (`#5865F2`) copied unmodified.
Component discordOAuthMark() {
  return svg(viewBox: '0 0 126.644 96', width: 100.percent, height: 100.percent, [
    path(
      [],
      fill: const Color('#5865F2'),
      d:
          'M81.15,0c-1.2376,2.1973-2.3489,4.4704-3.3591,6.794-9.5975-1.4396-19.3718-1.4396-28.9945,0-.985-2.3236-2.1'
          '216-4.5967-3.3591-6.794-9.0166,1.5407-17.8059,4.2431-26.1405,8.0568C2.779,32.5304-1.6914,56.3725.5312,7'
          '9.8863c9.6732,7.1476,20.5083,12.603,32.0505,16.0884,2.6014-3.4854,4.8998-7.1981,6.8698-11.0623-3.738-1'
          '.3891-7.3497-3.1318-10.8098-5.1523.9092-.6567,1.7932-1.3386,2.6519-1.9953,20.281,9.547,43.7696,9.547,6'
          '4.0758,0,.8587.7072,1.7427,1.3891,2.6519,1.9953-3.4601,2.0457-7.0718,3.7632-10.835,5.1776,1.97,3.8642,'
          '4.2683,7.5769,6.8698,11.0623,11.5419-3.4854,22.3769-8.9156,32.0509-16.0631,2.626-27.2771-4.496-50.9172'
          '-18.817-71.8548C98.9811,4.2684,90.1918,1.5659,81.1752.0505l-.0252-.0505ZM42.2802,65.4144c-6.2383,0-11.'
          '4159-5.6575-11.4159-12.6535s4.9755-12.6788,11.3907-12.6788,11.5169,5.708,11.4159,12.6788c-.101,6.9708-'
          '5.026,12.6535-11.3907,12.6535ZM84.3576,65.4144c-6.2637,0-11.3907-5.6575-11.3907-12.6535s4.9755-12.6788'
          ',11.3907-12.6788,11.4917,5.708,11.3906,12.6788c-.101,6.9708-5.026,12.6535-11.3906,12.6535Z',
    ),
  ]);
}

/// GitLab's "Tanuki" logomark. Fixed colors — never inverts.
///
/// Source: `about.gitlab.com/images/press/gitlab-logo-500-rgb.svg`, linked
/// from GitLab's official press kit (`about.gitlab.com/press/press-kit/`),
/// fetched 2026-08-15. Path data and the three shades
/// (`#E24329`/`#FC6D26`/`#FCA326`) copied unmodified; original used CSS
/// classes for the fills, inlined here as explicit `fill` values instead of
/// carrying a `<style>` element.
Component gitlabOAuthMark() {
  return svg(viewBox: '0 0 380 380', width: 100.percent, height: 100.percent, [
    path(
      [],
      fill: const Color('#E24329'),
      d:
          'M265.26416,174.37243l-.2134-.55822-21.19899-55.30908c-.4236-1.08359-1.18542-1.99642-2.17699-2.62689-.98'
          '837-.63373-2.14749-.93253-3.32305-.87014-1.1689.06239-2.29195.48925-3.20809,1.21821-.90957.73554-1.56'
          '629,1.73047-1.87493,2.85346l-14.31327,43.80662h-57.90965l-14.31327-43.80662c-.30864-1.12299-.96536-2.'
          '11791-1.87493-2.85346-.91614-.72895-2.03911-1.15582-3.20809-1.21821-1.17548-.06239-2.33468.23641-3.32'
          '297.87014-.99166.63047-1.75348,1.5433-2.17707,2.62689l-21.19891,55.31237-.21348.55493c-6.28158,16.385'
          '21-.92929,34.90803,13.05891,45.48782.02621.01641.04922.03611.07552.05582l.18719.14119,32.29094,24.173'
          '92,15.97151,12.09024,9.71951,7.34871c2.34117,1.77316,5.57877,1.77316,7.92002,0l9.71943-7.34871,15.968'
          '22-12.09024,32.48142-24.31511c.02958-.02299.05588-.04269.08538-.06568,13.97834-10.57977,19.32735-29.0'
          '9604,13.04905-45.47796Z',
    ),
    path(
      [],
      fill: const Color('#FC6D26'),
      d:
          'M265.26416,174.37243l-.2134-.55822c-10.5174,2.16062-20.20405,6.6099-28.49844,12.81593-.1346.0985-25.204'
          '97,19.05805-46.55171,35.19699,15.84998,11.98517,29.6477,22.40405,29.6477,22.40405l32.48142-24.31511c.'
          '02958-.02299.05588-.04269.08538-.06568,13.97834-10.57977,19.32735-29.09604,13.04905-45.47796Z',
    ),
    path(
      [],
      fill: const Color('#FCA326'),
      d:
          'M160.34962,244.23117l15.97151,12.09024,9.71951,7.34871c2.34117,1.77316,5.57877,1.77316,7.92002,0l9.71943'
          '-7.34871,15.96822-12.09024s-13.79772-10.41888-29.6477-22.40405c-15.85327,11.98517-29.65099,22.40405-2'
          '9.65099,22.40405Z',
    ),
    path(
      [],
      fill: const Color('#FC6D26'),
      d:
          'M143.44561,186.63014c-8.29111-6.20274-17.97446-10.65531-28.49507-12.81264l-.21348.55493c-6.28158,16.385'
          '21-.92929,34.90803,13.05891,45.48782.02621.01641.04922.03611.07552.05582l.18719.14119,32.29094,24.173'
          '92s13.79772-10.41888,29.65099-22.40405c-21.34673-16.13894-46.42031-35.09848-46.55499-35.19699Z',
    ),
  ]);
}

/// LinkedIn's "in" logomark. Fixed color — never inverts.
///
/// Source: inline `<symbol>` markup served on `brand.linkedin.com/in-logo`
/// itself (the 40x40 variant), fetched 2026-08-15 — the only official SVG
/// found; LinkedIn's downloadable brand package (`in-logo.zip`) is
/// PNG-only. Brand blue `#0A66C2` matches both this live markup and
/// LinkedIn's documented 2020 rebrand color, and matches the value already
/// baked into `OAuthProvider.linkedin`'s [OAuthBrand.background].
Component linkedinOAuthMark() {
  return svg(viewBox: '0 0 40 40', width: 100.percent, height: 100.percent, [
    path(
      [],
      fill: const Color('#0A66C2'),
      d:
          'm37 0h-34c-1.7 0-3 1.3-3 2.9v34.2c0 1.6 1.3 2.9 3 2.9h34c1.6 0 2.9-1.3 3-2.9v-34.2c0-1.6-1.3-2.9-3-2.9zm-'
          '25.1 34.1h-6v-19.1h5.9v19.1zm-3-21.7c-1.9 0-3.4-1.5-3.4-3.4s1.5-3.5 3.4-3.5 3.4 1.5 3.4 3.4c0 2-1.5 3.5'
          '-3.4 3.5zm25.2 21.7h-5.9v-9.3c0-2.2 0-5.1-3.1-5.1s-3.6 2.4-3.6 4.9v9.4h-5.9v-19h5.7v2.6h0.1c0.8-1.5 2.7'
          '-3.1 5.6-3.1 6 0 7.1 4 7.1 9.1v10.5z',
    ),
  ]);
}
