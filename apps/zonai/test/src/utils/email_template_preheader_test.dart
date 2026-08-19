import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/init_email_templates.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/email_template_render.dart';
import 'package:zonai/src/utils/email_template_variables.dart';

/// Renders [templateName] from [initEmailTemplates] against an in-memory FS.
String render(
  String templateName, {
  Map<String, dynamic> variables = const {},
  String? preheader,
}) {
  final memoryFs = MemoryFileSystem();

  return runScoped(() {
    memoryFs.directory('templates').createSync();
    memoryFs
        .file('templates/$templateName.html')
        .writeAsStringSync(initEmailTemplates[templateName]!);

    return renderEmailTemplate(
      templateName: templateName,
      variables: variables,
      appName: 'Test App',
      emailTemplatesPath: 'templates',
      preheader: preheader,
    );
  }, values: {fsProvider.overrideWith(() => memoryFs)});
}

void main() {
  group('preheader block', () {
    test('every built-in template carries one', () {
      for (final name in initEmailTemplates.keys) {
        expect(
          initEmailTemplates[name],
          contains('{{#preheader}}'),
          reason: '$name is missing the hidden preheader block',
        );
      }
    });

    test('renders the line inside a hidden block, above the greeting', () {
      final html = render('otp_code', preheader: 'Your code is waiting.');

      expect(html, contains('Your code is waiting.'));
      expect(html, contains('display:none'));
      // The whole point: the client reads it before anything visible.
      expect(
        html.indexOf('Your code is waiting.'),
        lessThan(html.indexOf('<p>Hi')),
      );
    });

    test('pads the snippet so visible copy does not run on into it', () {
      final html = render('otp_code', preheader: 'Short line.');
      final block = RegExp(
        r'Short line\.(.*?)</div>',
        dotAll: true,
      ).firstMatch(html)!.group(1)!;

      expect('&zwnj;'.allMatches(block).length, greaterThan(10));
    });

    test('renders no block at all when no preheader is set', () {
      final html = render('otp_code');

      expect(html, isNot(contains('display:none')));
      expect(html, isNot(contains('{{')));
    });

    test('treats a blank preheader as absent', () {
      // Mustache reads any string -- '' included -- as a truthy section, so a
      // blank value would otherwise render an empty hidden div.
      expect(
        render('otp_code', preheader: '   '),
        isNot(contains('display:none')),
      );
      expect(
        render('otp_code', variables: {'preheader': ''}),
        isNot(contains('display:none')),
      );
    });

    test('falls back to a preheader passed in variables', () {
      final html = render(
        'otp_code',
        variables: {'preheader': 'From the variables map.'},
      );

      expect(html, contains('From the variables map.'));
    });

    test('the argument wins over a preheader in variables', () {
      final html = render(
        'otp_code',
        variables: {'preheader': 'Loser.'},
        preheader: 'Winner.',
      );

      expect(html, contains('Winner.'));
      expect(html, isNot(contains('Loser.')));
    });

    test('is HTML-escaped, so copy cannot break the block', () {
      final html = render('otp_code', preheader: 'Tom & Jerry <b>hi</b>');

      expect(html, contains('Tom &amp; Jerry'));
      expect(html, isNot(contains('<b>hi</b>')));
    });
  });

  group('template authoring surface', () {
    test('preheader is not offered as an editable variable', () {
      // It is injected at render time from Email.preheader, the same as
      // appName -- prompting for it in the dev form would be a lie.
      expect(
        extractMustacheVariables(initEmailTemplates['otp_code']!),
        isNot(contains('preheader')),
      );
    });
  });
}
