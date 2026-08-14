/// A tiny build-time syntax highlighter.
///
/// The site only ever shows a handful of hand-written snippets, so pulling in a
/// full grammar engine would cost more than it returns. This scans a source
/// string once against an ordered rule list and emits `<span class="tk-…">`.
/// It runs during static rendering, so the browser receives plain markup.
library;

import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Languages the highlighter knows about.
enum Lang { dart, shell, http, yaml, none }

final class _Rule {
  const _Rule(this.pattern, this.token);

  final RegExp pattern;
  final String token;
}

const _dartKeywords =
    r'abstract|as|assert|async|await|base|break|case|catch|class|const|continue|covariant|default|deferred|do|'
    r'dynamic|else|enum|export|extends|extension|external|factory|final|finally|for|get|hide|if|implements|'
    r'import|in|interface|is|late|library|mixin|new|on|operator|part|required|rethrow|return|sealed|set|show|'
    r'static|super|switch|sync|this|throw|try|typedef|var|void|when|while|with|yield';

final _dartRules = <_Rule>[
  _Rule(RegExp(r'//[^\n]*'), 'cmt'),
  _Rule(RegExp(r'/\*[\s\S]*?\*/'), 'cmt'),
  _Rule(RegExp(r"r?'''[\s\S]*?'''"), 'str'),
  _Rule(RegExp(r"r?'(?:\\.|[^'\\\n])*'"), 'str'),
  _Rule(RegExp(r'r?"(?:\\.|[^"\\\n])*"'), 'str'),
  _Rule(RegExp(r'@[A-Za-z_]\w*'), 'ann'),
  _Rule(RegExp('\\b(?:$_dartKeywords)\\b'), 'kw'),
  _Rule(RegExp(r'\b(?:true|false|null)\b'), 'lit'),
  _Rule(RegExp(r'\b\d[\d_]*(?:\.\d+)?\b'), 'num'),
  _Rule(RegExp(r'\b[A-Z]\w*'), 'typ'),
  _Rule(RegExp(r'\b[a-z_]\w*(?=\s*\()'), 'fn'),
  _Rule(RegExp(r'\b[a-z_]\w*(?=:\s)'), 'arg'),
  _Rule(RegExp(r'[{}()\[\];,.=<>+\-*/?!&|:]'), 'pct'),
];

final _shellRules = <_Rule>[
  _Rule(RegExp(r'#[^\n]*'), 'cmt'),
  _Rule(RegExp(r"'(?:\\.|[^'\\])*'"), 'str'),
  _Rule(RegExp(r'"(?:\\.|[^"\\])*"'), 'str'),
  // A leading `$` prompt is chrome, not content.
  _Rule(RegExp(r'^\s*\$', multiLine: true), 'prompt'),
  _Rule(RegExp(r'(?:^|(?<=[\s$]))(?:\./)?zonai\b', multiLine: true), 'cmd'),
  _Rule(RegExp(r'(?:^|(?<=[\s$]))(?:dart|flutter|curl|cd|git|chmod|unzip)\b', multiLine: true), 'cmd'),
  _Rule(RegExp(r'--?[A-Za-z][\w-]*'), 'flag'),
  _Rule(RegExp(r'\b\d[\d_]*(?:\.\d+)?\b'), 'num'),
  _Rule(RegExp(r'[|&><]'), 'pct'),
];

final _httpRules = <_Rule>[
  _Rule(RegExp(r'\b(?:GET|POST|PATCH|PUT|DELETE)\b'), 'kw'),
  _Rule(RegExp(r'/[\w/*.-]*'), 'fn'),
  _Rule(RegExp(r'\?[^\s]*'), 'arg'),
  _Rule(RegExp(r'#[^\n]*'), 'cmt'),
];

final _yamlRules = <_Rule>[
  _Rule(RegExp(r'#[^\n]*'), 'cmt'),
  _Rule(RegExp(r'^\s*-?\s*[\w.-]+(?=:)', multiLine: true), 'arg'),
  _Rule(RegExp(r"'(?:[^'])*'"), 'str'),
  _Rule(RegExp(r'\b\d[\d_]*(?:\.\d+)?\b'), 'num'),
  _Rule(RegExp(r'[:\-]'), 'pct'),
];

List<_Rule> _rulesFor(Lang lang) => switch (lang) {
  Lang.dart => _dartRules,
  Lang.shell => _shellRules,
  Lang.http => _httpRules,
  Lang.yaml => _yamlRules,
  Lang.none => const [],
};

/// Splits [source] into styled spans. Unmatched text is emitted verbatim so no
/// character is ever dropped, whatever the rules do or do not cover.
List<Component> highlight(String source, Lang lang) {
  final rules = _rulesFor(lang);
  if (rules.isEmpty) return [.text(source)];

  final out = <Component>[];
  final plain = StringBuffer();

  void flush() {
    if (plain.isEmpty) return;
    out.add(.text(plain.toString()));
    plain.clear();
  }

  var i = 0;
  while (i < source.length) {
    _Rule? hit;
    Match? match;
    for (final rule in rules) {
      final m = rule.pattern.matchAsPrefix(source, i);
      if (m != null && m.end > m.start) {
        hit = rule;
        match = m;
        break;
      }
    }

    if (hit == null || match == null) {
      plain.write(source[i]);
      i += 1;
      continue;
    }

    flush();
    out.add(span(classes: 'tk-${hit.token}', [.text(source.substring(match.start, match.end))]));
    i = match.end;
  }

  flush();
  return out;
}

/// A syntax-highlighted code block.
class CodeBlock extends StatelessComponent {
  const CodeBlock(this.source, {this.lang = Lang.dart, this.classes, super.key});

  final String source;
  final Lang lang;
  final String? classes;

  @override
  Component build(BuildContext context) {
    return pre(classes: ['code', if (classes != null) classes!].join(' '), [
      code(highlight(source.trimRight(), lang)),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.code', [
      css('&').styles(
        margin: .zero,
        padding: .all(20.px),
        overflow: .only(x: .auto),
        color: .variable('--fg-dim'),
        fontSize: 13.px,
        lineHeight: 1.75.em,
        raw: {'tab-size': '2'},
      ),
      css('&::-webkit-scrollbar').styles(height: 8.px),
      css('&::-webkit-scrollbar-thumb').styles(
        radius: .circular(4.px),
        backgroundColor: .variable('--edge-2'),
      ),
      css('code').styles(fontSize: .inherit, raw: {'font-family': 'inherit'}),
      css('.tk-cmt').styles(color: .variable('--fg-mute'), fontStyle: .italic),
      css('.tk-str').styles(color: .variable('--gold')),
      css('.tk-kw').styles(color: .variable('--violet')),
      css('.tk-lit').styles(color: .variable('--violet')),
      css('.tk-typ').styles(color: .variable('--zon-soft')),
      css('.tk-fn').styles(color: .variable('--fg')),
      css('.tk-arg').styles(color: .variable('--sky')),
      css('.tk-num').styles(color: .variable('--sky')),
      css('.tk-ann').styles(color: .variable('--rose')),
      css('.tk-pct').styles(color: .variable('--fg-mute')),
      css('.tk-cmd').styles(color: .variable('--zon'), fontWeight: .w600),
      css('.tk-flag').styles(color: .variable('--sky')),
      css('.tk-prompt').styles(color: .variable('--zon-deep'), userSelect: .none),
    ]),
    css.media(MediaQuery.screen(maxWidth: 640.px), [
      css('.code').styles(padding: .all(16.px), fontSize: 12.px),
    ]),
  ];
}

/// A code block dressed as an editor window: title bar, filename, traffic lights.
class CodeWindow extends StatelessComponent {
  const CodeWindow({
    required this.filename,
    required this.source,
    this.lang = Lang.dart,
    this.badge,
    this.classes,
    super.key,
  });

  final String filename;
  final String source;
  final Lang lang;
  final String? badge;
  final String? classes;

  @override
  Component build(BuildContext context) {
    return div(classes: ['pane', 'window', if (classes != null) classes!].join(' '), [
      div(classes: 'window-bar', [
        span(classes: 'dots', [span([]), span([]), span([])]),
        span(classes: 'window-name', [.text(filename)]),
        if (badge case final text?) span(classes: 'window-badge', [.text(text)]),
      ]),
      CodeBlock(source, lang: lang),
    ]);
  }

  // The title-bar rules are deliberately NOT nested under `.window`: the hero's
  // endpoint list and the tabbed viewer reuse the same bar without being one.
  @css
  static List<StyleRule> get styles => [
    css('.window').styles(
      display: .flex,
      flexDirection: .column,
      backgroundColor: .variable('--ink'),
      raw: {'box-shadow': '0 24px 60px -28px rgba(0,0,0,0.85)'},
    ),
    css('.window-bar').styles(
      display: .flex,
      padding: .symmetric(vertical: 10.px, horizontal: 14.px),
      border: .only(
        bottom: BorderSide.solid(color: .variable('--edge'), width: 1.px),
      ),
      alignItems: .center,
      gap: .all(12.px),
      backgroundColor: .variable('--slab'),
    ),
    css('.dots').styles(display: .flex, gap: .all(6.px), raw: {'flex': '0 0 auto'}),
    css('.dots > span').styles(
      width: 9.px,
      height: 9.px,
      radius: .circular(50.percent),
      backgroundColor: .variable('--edge-2'),
    ),
    css('.dots > span:first-child').styles(backgroundColor: .rgba(255, 122, 107, 0.55)),
    css('.dots > span:nth-child(2)').styles(backgroundColor: .rgba(240, 184, 64, 0.5)),
    css('.dots > span:nth-child(3)').styles(backgroundColor: .rgba(47, 224, 172, 0.5)),
    css('.window-name').styles(
      overflow: .hidden,
      color: .variable('--fg-mute'),
      fontFamily: .variable('--mono'),
      fontSize: 12.px,
      textOverflow: .ellipsis,
      whiteSpace: .noWrap,
      // Lets the ellipsis actually engage instead of widening the title bar.
      raw: {'min-width': '0'},
    ),
    css('.window-badge').styles(
      padding: .symmetric(vertical: 2.px, horizontal: 8.px),
      radius: .circular(999.px),
      color: .variable('--zon'),
      fontFamily: .variable('--mono'),
      fontSize: 10.px,
      letterSpacing: 0.6.px,
      whiteSpace: .noWrap,
      backgroundColor: .rgba(47, 224, 172, 0.1),
      raw: {'margin-left': 'auto', 'flex': '0 0 auto', 'border': '1px solid rgba(47,224,172,0.2)'},
    ),
  ];
}
