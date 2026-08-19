/// Guards every content page against the template engine that renders it.
///
/// `main.server.dart` hands each page to `MustacheTemplateEngine` **before**
/// the markdown is parsed, so `{{...}}` written as an example is not example
/// text — it is a tag. Two ways that bites, both of which had already shipped
/// when this test was written (2026-08-19):
///
///   * A value tag is substituted with the empty string, so the published
///     `/email/custom-templates` read `<p>Hi ,</p>` where the code block says
///     `<p>Hi {{customerName}},</p>`. Nothing failed; the page was just wrong.
///   * A section tag with no partner **throws**, and jaspr aborts the whole
///     build. One prose mention of `{{#preheader}}` took the entire docs
///     deploy down, and it did so on a commit whose own tests were green,
///     because nothing here parsed a page the way the site does.
///
/// The remedy a page uses is Mustache's own delimiter-change tag as the first
/// thing in its content, which makes the rest of the file inert. This test
/// does not care which remedy is used — it renders the page exactly as the
/// site does and asserts the result still contains what the source wrote.
///
/// The second test here covers the stage immediately after: the markdown
/// parser, which parses embedded HTML strictly. `--` inside an HTML comment is
/// illegal, and jaspr_content turns it into `Assertion failed: "Unexpected
/// parse error: unexpected-char-in-comment"` — another whole-build failure,
/// found the same day by fixing the first bug with a comment that contained a
/// double hyphen.
library;

import 'dart:io';

import 'package:mustache_template/mustache_template.dart';
import 'package:test/test.dart';

/// Kept in step with `MustacheTemplateEngine`'s defaults, which
/// `main.server.dart` takes as-is.
const _delimiters = '{{ }}';

/// Pages that use Mustache *on purpose* and must keep being rendered.
///
/// `about.md` loops over `site.social` to build its links, so its tags are
/// supposed to disappear into output. Anything added here is opting out of the
/// guard, so it needs a reason of the same kind.
const _rendersMustacheOnPurpose = {'content/about.md'};

/// A tag as written in the source: `{{name}}`, `{{#items}}`, `{{/items}}`.
final _tag = RegExp(r'\{\{[#/^]?([A-Za-z][\w.]*)\}\}');

/// An HTML comment, including the unterminated case — `<!--` with no `-->` is
/// itself a parse error, so it must not be quietly skipped.
final _htmlComment = RegExp(r'<!--(.*?)(-->|$)', dotAll: true);

/// jaspr_content strips frontmatter before the engine sees the page.
String _body(String source) {
  if (!source.startsWith('---')) return source;
  final close = source.indexOf('\n---', 3);
  if (close == -1) return source;
  return source.substring(source.indexOf('\n', close + 1) + 1);
}

void main() {
  final pages =
      Directory('content').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('there are content pages to check', () {
    expect(pages, isNotEmpty);
  });

  for (final page in pages) {
    test('${page.path} has no double hyphen inside an HTML comment', () {
      final source = page.readAsStringSync();
      final offenders = <String>[];
      for (final m in _htmlComment.allMatches(source)) {
        if (m.group(2) != '-->') {
          offenders.add('unterminated comment at offset ${m.start}');
        } else if (m.group(1)!.contains('--')) {
          offenders.add('`--` inside the comment at offset ${m.start}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'The markdown parser rejects this and fails the whole docs build '
            'with "unexpected-char-in-comment". Use an em dash.',
      );
    });
  }

  for (final page in pages) {
    final path = page.path;
    if (_rendersMustacheOnPurpose.contains(path)) continue;

    test('$path survives the template engine intact', () {
      final body = _body(page.readAsStringSync());

      final String rendered;
      try {
        rendered = Template(
          body,
          lenient: true,
          delimiters: _delimiters,
        ).renderString({});
      } on TemplateException catch (e) {
        fail(
          'Mustache refused to parse this page, which fails the docs build '
          'outright rather than rendering it wrong: $e\n'
          'Put a delimiter-change tag at the very top of the page content.',
        );
      }

      final missing = {
        for (final m in _tag.allMatches(body))
          if (!rendered.contains(m.group(0)!)) m.group(0)!,
      };

      expect(
        missing,
        isEmpty,
        reason:
            'The template engine substituted these away, so they will not '
            'appear on the published page. Put a delimiter-change tag at the '
            'very top of the page content, or add the page to '
            '_rendersMustacheOnPurpose if the substitution is the point.',
      );
    });
  }
}
