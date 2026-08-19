/// Guards the shipped email templates against losing their preheader block.
///
/// These are the files a real project copies, so a template that drops the
/// hidden block silently goes back to previewing as "Hi {{name}}," in the inbox
/// -- nothing else in the suite would notice.
library;

import 'dart:io';

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/email_template_render.dart';

const _templatesPath = 'lib/src/email_templates';

T _withRealFs<T>(T Function() body) =>
    runScoped(body, values: {fsProvider.overrideWith(LocalFileSystem.new)});

/// Approximates what a mail client scrapes for the inbox snippet: the body's
/// text with markup and comments removed, in document order.
///
/// Hidden text is deliberately kept -- being invisible to the eye but visible
/// to this scrape is the whole point of a preheader.
String _snippet(String html) {
  final body = html.substring(html.indexOf('<body'));
  return body
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), '')
      .replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ')
      .replaceAll(RegExp(r'&[#\w]+;'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void main() {
  final names = [
    for (final file in Directory(_templatesPath).listSync().whereType<File>())
      if (file.path.endsWith('.html'))
        file.uri.pathSegments.last.replaceAll('.html', ''),
  ]..sort();

  test('there are templates to check', () {
    expect(names, isNotEmpty);
  });

  for (final name in names) {
    group('$name.html', () {
      test('puts the preheader at the head of the inbox snippet', () {
        final html = _withRealFs(
          () => renderEmailTemplate(
            templateName: name,
            variables: const {'email': 'user@example.com'},
            appName: 'Test App',
            emailTemplatesPath: _templatesPath,
            preheader: 'PREVIEW-LINE',
          ),
        );

        expect(html, contains('PREVIEW-LINE'));
        expect(html, contains('display: none'));
        // What the inbox would show: the preview line, and nothing scraped
        // from the visible body ahead of it.
        expect(_snippet(html), startsWith('PREVIEW-LINE'));
      });

      test('renders no hidden block when no preheader is set', () {
        final html = _withRealFs(
          () => renderEmailTemplate(
            templateName: name,
            variables: const {'email': 'user@example.com'},
            appName: 'Test App',
            emailTemplatesPath: _templatesPath,
          ),
        );

        expect(html, isNot(contains('display: none')));
        expect(html, isNot(contains('{{')));
      });
    });
  }
}
