import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/email_template_render.dart';
import 'package:zonai/src/utils/email_template_variables.dart';

void main() {
  group('extractMustacheVariables', () {
    test('collects unique variable names and excludes appName', () {
      const source = '''
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>{{email}} — {{otp}}</p>
<p>{{appName}}</p>
''';

      expect(extractMustacheVariables(source), ['email', 'name', 'otp']);
    });
  });

  group('missingTemplateVariableKeys', () {
    test('returns keys that are absent or blank', () {
      expect(
        missingTemplateVariableKeys(
          ['email', 'name', 'otp'],
          {'email': 'a@b.com', 'name': '   '},
        ),
        ['name', 'otp'],
      );
    });
  });

  group('formatVariableLines / parseVariableLines', () {
    test('round-trips sorted key=value lines', () {
      const input = '''
email=user@example.com
name=Test User
''';

      expect(
        formatVariableLines(parseVariableLines(input)),
        'email=user@example.com\nname=Test User',
      );
    });

    test('parseVariableLines keeps custom keys and ignores comments', () {
      const input = '''
# preview values
name=Ada
customField=hello world
invalid-line
''';

      expect(parseVariableLines(input), {
        'name': 'Ada',
        'customField': 'hello world',
      });
    });
  });

  group('renderEmailTemplate', () {
    test('substitutes variables and appName', () {
      final memoryFs = MemoryFileSystem();

      runScoped(() {
        memoryFs.directory('templates').createSync();
        memoryFs.file('templates/preview_test.html').writeAsStringSync('''
<p>Hi{{#name}} {{name}}{{/name}},</p>
<p>Confirm <strong>{{email}}</strong> for {{appName}}.</p>
''');

        final html = renderEmailTemplate(
          templateName: 'preview_test',
          variables: {'name': 'Ada', 'email': 'ada@example.com'},
          appName: 'Test App',
          emailTemplatesPath: 'templates',
        );

        expect(html, contains('Hi Ada'));
        expect(html, contains('ada@example.com'));
        expect(html, contains('Test App'));
      }, values: {fsProvider.overrideWith(() => memoryFs)});
    });
  });
}
