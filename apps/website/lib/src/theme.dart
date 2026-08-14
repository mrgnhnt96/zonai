/// Design tokens and global styles for the Zonai marketing site.
///
/// The palette is drawn from the logo: a carved stone rune lit from within.
/// Surfaces are cold basalt, the accent is the green energy in the rune's core,
/// and gold is reserved for the few "this is the good part" moments.
library;

import 'package:jaspr/dom.dart';

import 'gen/version.dart';

// Re-exported so every component keeps importing the version from `theme.dart`
// and never has to know it is generated.
export 'gen/version.dart';

/// Canonical off-site URLs, kept in one place so a domain change is one edit.
abstract final class Links {
  static const docs = 'https://docs.zonai.dev';
  static const quickStart = 'https://docs.zonai.dev/getting-started/quick-start';
  static const installation = 'https://docs.zonai.dev/getting-started/installation';
  static const streaming = 'https://docs.zonai.dev/operations/streaming';
  static const rules = 'https://docs.zonai.dev/rules/overview';
  static const pipeline = 'https://docs.zonai.dev/core-concepts/request-pipeline';
  static const client = 'https://docs.zonai.dev/dart-client/overview';
  static const deployment = 'https://docs.zonai.dev/deployment/building-for-production';
  static const llms = 'https://docs.zonai.dev/llms.txt';
  static const github = 'https://github.com/mrgnhnt96/zonai';

  /// The newest **CLI** release.
  ///
  /// Pinned to the tag on purpose. `releases/latest` currently resolves to
  /// `zonai_client-v0.1.0` — publishing a pub package cuts a release that
  /// carries no CLI asset, and GitHub's "latest" pointer follows it. Bump this
  /// with [zonaiVersion]; see [downloads].
  static const release = 'https://github.com/mrgnhnt96/zonai/releases/tag/v$zonaiVersion';
  static const allReleases = 'https://github.com/mrgnhnt96/zonai/releases';
  static const issues = 'https://github.com/mrgnhnt96/zonai/issues';
  static const pubClient = 'https://pub.dev/packages/zonai_client';
  static const pubSchema = 'https://pub.dev/packages/zonai_schema';
}

/// The hero's copy-paste install line.
///
/// Deliberately pinned to a tag rather than `releases/latest/download/…`:
/// publishing `zonai_client` / `zonai_schema` creates package-tagged releases
/// that carry no CLI asset, so GitHub's "latest" pointer moves off the CLI and
/// the `latest` URL 404s. Bump this with [zonaiVersion].
const installCommand =
    'curl -fsSL https://github.com/mrgnhnt96/zonai/releases/download/v$zonaiVersion/zonai '
    '-o zonai && chmod +x zonai';

const _assetBase = 'https://github.com/mrgnhnt96/zonai/releases/download/v$zonaiVersion';

/// One downloadable build. [note] is the arch line, [size] the real asset size.
typedef Download = ({String os, String note, String size, String href, String icon});

/// The self-extracting build: every macOS/Linux arch in one file, picked at
/// runtime. Not a Windows executable — Windows needs [windowsDownload].
const universalDownload = (
  os: 'macOS + Linux',
  note: 'Universal — detects your OS and architecture',
  size: '34.9 MiB',
  href: '$_assetBase/zonai',
  icon: 'spark',
);

const windowsDownload = (
  os: 'Windows',
  note: 'x64',
  size: '12.0 MiB',
  href: '$_assetBase/zonai-windows-x64.zip',
  icon: 'windows',
);

/// Per-platform builds, for when the universal file is more than you want.
const downloads = <Download>[
  (
    os: 'macOS',
    note: 'Apple Silicon (arm64)',
    size: '11.8 MiB',
    href: '$_assetBase/zonai-macos-arm64.zip',
    icon: 'apple',
  ),
  (os: 'macOS', note: 'Intel (x64)', size: '12.5 MiB', href: '$_assetBase/zonai-macos-x64.zip', icon: 'apple'),
  (os: 'Linux', note: 'x64', size: '11.9 MiB', href: '$_assetBase/zonai-linux-x64.zip', icon: 'linux'),
  (os: 'Linux', note: 'arm64', size: '11.5 MiB', href: '$_assetBase/zonai-linux-arm64.zip', icon: 'linux'),
  windowsDownload,
];

/// Design tokens, emitted once as CSS custom properties on `:root`.
///
/// Everything downstream references `var(--…)` so the whole site can be
/// re-tuned from this map alone.
const _tokens = {
  // Surfaces — basalt, darkest first.
  '--void': '#05080A',
  '--ink': '#080D0F',
  '--slab': '#0C1316',
  '--slab-2': '#111A1E',
  '--slab-3': '#162126',
  '--edge': '#1C2A30',
  '--edge-2': '#26383F',

  // Text.
  '--fg': '#E4EFF1',
  '--fg-dim': '#A8BCC0',
  '--fg-mute': '#6E858B',

  // The rune's energy.
  '--zon': '#2FE0AC',
  '--zon-soft': '#7BF2CE',
  '--zon-deep': '#0B8F6C',
  '--zon-glow': 'rgba(47, 224, 172, 0.28)',

  // Support colors.
  '--gold': '#F0B840',
  '--sky': '#5BC8FA',
  '--rose': '#FF7A6B',
  '--violet': '#A98CFF',

  // Type.
  '--sans': "'Space Grotesk', ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif",
  '--body': "'Inter', ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif",
  '--mono': "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",

  // Layout.
  '--max': '1160px',
  '--gutter': '24px',
};

@css
List<StyleRule> get globalStyles => [
  css(':root').styles(raw: _tokens),

  css('*, *::before, *::after').styles(boxSizing: .borderBox),

  css('html').styles(
    raw: {
      'scroll-behavior': 'smooth',
      'scroll-padding-top': '96px',
      '-webkit-text-size-adjust': '100%',
    },
  ),

  css('body').styles(
    margin: .zero,
    color: .variable('--fg'),
    fontFamily: .variable('--body'),
    fontSize: 16.px,
    lineHeight: 1.65.em,
    backgroundColor: .variable('--void'),
    raw: {
      '-webkit-font-smoothing': 'antialiased',
      '-moz-osx-font-smoothing': 'grayscale',
      'overflow-x': 'hidden',
      'text-rendering': 'optimizeLegibility',
    },
  ),

  // Ambient light: two soft pools of energy behind everything, plus a faint
  // grid so the dark areas read as "surface" rather than "void".
  css('body::before').styles(
    content: '""',
    position: .fixed(top: .zero, left: .zero, right: .zero, bottom: .zero),
    zIndex: ZIndex(0),
    pointerEvents: .none,
    raw: {
      'background':
          'radial-gradient(900px 620px at 18% -8%, rgba(47,224,172,0.10), transparent 62%),'
          'radial-gradient(760px 520px at 88% 4%, rgba(91,200,250,0.07), transparent 60%),'
          'radial-gradient(1100px 700px at 50% 108%, rgba(169,140,255,0.06), transparent 66%)',
    },
  ),
  css('body::after').styles(
    content: '""',
    position: .fixed(top: .zero, left: .zero, right: .zero, bottom: .zero),
    zIndex: ZIndex(0),
    opacity: 0.5,
    pointerEvents: .none,
    raw: {
      'background-image':
          'linear-gradient(rgba(255,255,255,0.022) 1px, transparent 1px),'
          'linear-gradient(90deg, rgba(255,255,255,0.022) 1px, transparent 1px)',
      'background-size': '64px 64px',
      'mask-image': 'radial-gradient(ellipse 120% 78% at 50% 0%, #000 32%, transparent 78%)',
      '-webkit-mask-image': 'radial-gradient(ellipse 120% 78% at 50% 0%, #000 32%, transparent 78%)',
    },
  ),

  // Everything the user actually reads sits above the ambient layers.
  css('main, header, footer').styles(position: .relative(), zIndex: ZIndex(1)),

  css('h1, h2, h3, h4').styles(
    margin: .zero,
    fontFamily: .variable('--sans'),
    fontWeight: .w600,
    lineHeight: 1.12.em,
    raw: {'letter-spacing': '-0.025em', 'text-wrap': 'balance'},
  ),
  css('p').styles(margin: .zero, raw: {'text-wrap': 'pretty'}),

  css('a').styles(
    color: .variable('--zon'),
    textDecoration: .none,
    transition: Transition('color', duration: 160.ms),
  ),
  css('a:hover').styles(color: .variable('--zon-soft')),

  css('code, pre').styles(fontFamily: .variable('--mono')),

  css('::selection').styles(color: .variable('--void'), backgroundColor: .variable('--zon-soft')),

  css(':focus-visible').styles(
    outline: Outline(color: .variable('--zon'), style: .solid, width: OutlineWidth(2.px)),
    raw: {'outline-offset': '3px', 'border-radius': '6px'},
  ),

  // Shared layout primitives -------------------------------------------------
  css('.wrap').styles(
    width: 100.percent,
    maxWidth: .variable('--max'),
    padding: .symmetric(horizontal: .variable('--gutter')),
    margin: .symmetric(horizontal: .auto),
  ),

  // Section eyebrow: a small monospace label above every section heading.
  css('.eyebrow').styles(
    display: .flex,
    alignItems: .center,
    gap: .all(9.px),
    color: .variable('--zon'),
    fontFamily: .variable('--mono'),
    fontSize: 12.px,
    fontWeight: .w500,
    textTransform: .upperCase,
    letterSpacing: 1.6.px,
  ),
  css('.eyebrow::before').styles(
    content: '""',
    width: 22.px,
    height: 1.px,
    backgroundColor: .variable('--zon'),
    raw: {'box-shadow': '0 0 10px var(--zon)', 'flex': '0 0 auto'},
  ),

  css('.lede').styles(
    maxWidth: 620.px,
    color: .variable('--fg-dim'),
    fontSize: 17.px,
    lineHeight: 1.7.em,
  ),

  // A pane is the site's one container shape: dark slab, hairline edge.
  css('.pane').styles(
    border: .all(color: .variable('--edge'), width: 1.px),
    radius: .circular(14.px),
    overflow: .hidden,
    backgroundColor: .variable('--slab'),
  ),

  // Shared keyframes. These live here rather than beside their one caller
  // because `css.keyframes` cannot be nested inside a selector block, and
  // `pulse-fade` is driven by several components.
  css.keyframes('pulse-fade', {
    '0%, 100%': Styles(opacity: 1),
    '50%': Styles(opacity: 0.25),
  }),

  // Respect users who would rather the page held still.
  css.media(MediaQuery.raw('(prefers-reduced-motion: reduce)'), [
    css('*, *::before, *::after').styles(
      raw: {
        'animation-duration': '0.001ms !important',
        'animation-iteration-count': '1 !important',
        'transition-duration': '0.001ms !important',
        'scroll-behavior': 'auto !important',
      },
    ),
  ]),

  css.media(MediaQuery.screen(maxWidth: 640.px), [
    css(':root').styles(raw: {'--gutter': '18px'}),
    css('body').styles(fontSize: 15.px),
  ]),
];
