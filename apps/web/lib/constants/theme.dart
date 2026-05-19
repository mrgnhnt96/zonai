import 'package:jaspr/dom.dart';

const primaryColor = Color.variable('--zonai-primary');
const primaryHoverColor = Color.variable('--zonai-primary-hover');
const fgColor = Color.variable('--zonai-fg');
const bgColor = Color.variable('--zonai-bg');
const surfaceColor = Color.variable('--zonai-surface');
const borderColor = Color.variable('--zonai-border');
const mutedColor = Color.variable('--zonai-muted');
const hoverColor = Color.variable('--zonai-hover');
const selectedBgColor = Color.variable('--zonai-selected-bg');
const errorColor = Color.variable('--zonai-error');
const errorBgColor = Color.variable('--zonai-error-bg');
const errorBorderColor = Color.variable('--zonai-error-border');
const errorFgColor = Color.variable('--zonai-error-fg');
const tableHeaderBgColor = Color.variable('--zonai-table-header-bg');
const onPrimaryColor = Color.variable('--zonai-on-primary');

const _lightTokens = {
  '--zonai-bg': '#f1f5f9',
  '--zonai-fg': '#0f172a',
  '--zonai-surface': '#ffffff',
  '--zonai-border': '#e2e8f0',
  '--zonai-primary': '#01589B',
  '--zonai-primary-hover': '#014a84',
  '--zonai-on-primary': '#ffffff',
  '--zonai-muted': '#64748b',
  '--zonai-hover': '#f8fafc',
  '--zonai-selected-bg': '#eff6ff',
  '--zonai-error': '#b91c1c',
  '--zonai-error-bg': '#fef2f2',
  '--zonai-error-border': '#fecaca',
  '--zonai-error-fg': '#991b1b',
  '--zonai-table-header-bg': '#f8fafc',
  '--zonai-shadow': '0 12px 40px -8px rgb(0 0 0 / 0.08)',
  'color-scheme': 'light',
};

const _darkTokens = {
  '--zonai-bg': '#0f172a',
  '--zonai-fg': '#f1f5f9',
  '--zonai-surface': '#1e293b',
  '--zonai-border': '#334155',
  '--zonai-primary': '#38bdf8',
  '--zonai-primary-hover': '#0ea5e9',
  '--zonai-on-primary': '#0f172a',
  '--zonai-muted': '#94a3b8',
  '--zonai-hover': '#334155',
  '--zonai-selected-bg': '#1e3a5f',
  '--zonai-error': '#fca5a5',
  '--zonai-error-bg': '#450a0a',
  '--zonai-error-border': '#7f1d1d',
  '--zonai-error-fg': '#fecaca',
  '--zonai-table-header-bg': '#334155',
  '--zonai-shadow': '0 12px 40px -8px rgb(0 0 0 / 0.45)',
  'color-scheme': 'dark',
};

/// Inline script that applies a stored theme before paint to avoid a flash.
const themeBootstrapScript = '''
(function () {
  try {
    var t = localStorage.getItem('zonai_theme');
    if (t === 'dark' || t === 'light') {
      document.documentElement.setAttribute('data-theme', t);
    }
  } catch (e) {}
})();
''';

@css
List<StyleRule> get styles => [
  css.import('https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap'),
  css(':root').styles(
    raw: _lightTokens,
  ),
  css.media(
    MediaQuery.all(prefersColorScheme: ColorScheme.dark),
    [
      css(':root:not([data-theme="light"])').styles(raw: _darkTokens),
    ],
  ),
  css(':root[data-theme="dark"]').styles(raw: _darkTokens),
  css(':root[data-theme="light"]').styles(raw: _lightTokens),
  css('html, body').styles(
    width: 100.percent,
    minHeight: 100.vh,
    padding: .zero,
    margin: .zero,
    boxSizing: .borderBox,
    fontFamily: const .list([FontFamily('Inter'), FontFamilies.sansSerif]),
    backgroundColor: bgColor,
    color: fgColor,
  ),
  css('*', [css('&').styles(boxSizing: .inherit)]),
];
