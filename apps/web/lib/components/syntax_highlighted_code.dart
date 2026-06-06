import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:opal/opal.dart';

import '../utils/opal_highlight_classes.dart';

enum SyntaxHighlightLanguage { json, dart }

/// Renders [source] as a `<code>` block with [opal]-based syntax highlighting.
class SyntaxHighlightedCode extends StatelessComponent {
  const SyntaxHighlightedCode({required this.source, required this.language, this.extraClasses, super.key});

  final String source;
  final SyntaxHighlightLanguage language;

  /// Additional classes merged onto the root `<code>` element.
  final String? extraClasses;

  @override
  Component build(BuildContext context) {
    final classes = ['syntax-highlighted-code', if (extraClasses != null) extraClasses!].join(' ');

    return code(classes: classes, highlightedSpans(source, language));
  }
}

List<Component> highlightedSpans(String source, SyntaxHighlightLanguage language) {
  if (source.isEmpty) return [];

  final lang = switch (language) {
    SyntaxHighlightLanguage.json => BuiltInLanguages.json,
    SyntaxHighlightLanguage.dart => BuiltInLanguages.dart,
  };
  final lines = const LineSplitter().convert(source);
  final lineTokens = lang.tokenize(lines);
  final spans = <Component>[];

  for (var lineIndex = 0; lineIndex < lineTokens.length; lineIndex++) {
    if (lineIndex > 0) {
      spans.add(span(classes: 'syntax-hl-ws', [.text('\n')]));
    }
    for (final token in lineTokens[lineIndex]) {
      spans.add(_highlightTokenSpan(token));
    }
  }

  return spans;
}

Component _highlightTokenSpan(TaggedToken token) {
  if (opalTokenCssClass(token.tags) case final cssClass?) {
    return span(classes: cssClass, [.text(token.content)]);
  }
  return span([.text(token.content)]);
}

/// Reconstructs visible text after [highlightedSpans] (line breaks preserved).
String highlightedSourceText(String source, SyntaxHighlightLanguage language) {
  if (source.isEmpty) return '';

  final lang = switch (language) {
    SyntaxHighlightLanguage.json => BuiltInLanguages.json,
    SyntaxHighlightLanguage.dart => BuiltInLanguages.dart,
  };
  final lines = const LineSplitter().convert(source);
  final lineTokens = lang.tokenize(lines);
  final buffer = StringBuffer();

  for (var lineIndex = 0; lineIndex < lineTokens.length; lineIndex++) {
    if (lineIndex > 0) buffer.writeln();
    for (final token in lineTokens[lineIndex]) {
      buffer.write(token.content);
    }
  }

  return buffer.toString();
}

@css
List<StyleRule> get syntaxHighlightedCodeStyles => [
  css('.syntax-highlighted-code').styles(
    display: .block,
    margin: .zero,
    padding: .zero,
    color: const Color('#e2e8f0'),
    whiteSpace: WhiteSpace.preWrap,
    raw: const {'font-family': 'inherit', 'font-size': 'inherit', 'line-height': 'inherit', 'tab-size': 'inherit'},
  ),
  css('.syntax-highlighted-code .syntax-hl-key').styles(color: const Color('#7dd3fc')),
  css('.syntax-highlighted-code .syntax-hl-string').styles(color: const Color('#86efac')),
  css('.syntax-highlighted-code .syntax-hl-number').styles(color: const Color('#fcd34d')),
  css('.syntax-highlighted-code .syntax-hl-bool').styles(color: const Color('#f9a8d4')),
  css('.syntax-highlighted-code .syntax-hl-null').styles(color: const Color('#c4b5fd')),
  css('.syntax-highlighted-code .syntax-hl-punct').styles(color: const Color('#64748b')),
  css('.syntax-highlighted-code .syntax-hl-ws').styles(color: const Color('#e2e8f0')),
  css('.syntax-highlighted-code .syntax-hl-keyword').styles(color: const Color('#c4b5fd')),
  css('.syntax-highlighted-code .syntax-hl-type').styles(color: const Color('#7dd3fc')),
  css('.syntax-highlighted-code .syntax-hl-call').styles(color: const Color('#fcd34d')),
  css('.syntax-highlighted-code .syntax-hl-comment').styles(color: const Color('#64748b')),
  css('.syntax-highlighted-code .syntax-hl-annotation').styles(color: const Color('#f9a8d4')),
  css('.syntax-highlighted-code .syntax-hl-operator').styles(color: const Color('#94a3b8')),
];
