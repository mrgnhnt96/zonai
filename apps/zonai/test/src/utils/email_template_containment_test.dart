import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/email_template_render.dart';

/// The template name is joined onto the templates directory and read off disk.
/// Before this was checked, `POST /email` let an unauthenticated caller choose
/// that name -- so any `.html` file the process could read was readable over
/// the network, and `fs.path.join` treats an absolute second argument as a
/// reset rather than as a child.
void main() {
  group('isValidEmailTemplateName', () {
    test('accepts an ordinary template name', () {
      expect(isValidEmailTemplateName('otp_code'), isTrue);
      expect(isValidEmailTemplateName('password_reset'), isTrue);
    });

    test('rejects parent-directory traversal', () {
      expect(isValidEmailTemplateName('../../../../etc/hosts'), isFalse);
      expect(isValidEmailTemplateName('..'), isFalse);
      expect(isValidEmailTemplateName('../secrets'), isFalse);
    });

    test('rejects an absolute path, which join treats as a reset', () {
      // fs.path.join('/templates', '/etc/passwd') == '/etc/passwd'
      expect(isValidEmailTemplateName('/etc/passwd'), isFalse);
    });

    test('rejects a nested path and a Windows separator', () {
      expect(isValidEmailTemplateName('sub/dir/template'), isFalse);
      expect(
        isValidEmailTemplateName(r'..\..\windows\system32\config'),
        isFalse,
      );
    });

    test('rejects an empty name', () {
      expect(isValidEmailTemplateName(''), isFalse);
    });
  });

  group('renderEmailTemplate', () {
    late MemoryFileSystem memoryFs;

    setUp(() {
      memoryFs = MemoryFileSystem.test();
    });

    T withFs<T>(T Function() body) =>
        runScoped(body, values: {fsProvider.overrideWith(() => memoryFs)});

    test('renders a template that lives inside the templates dir', () {
      withFs(() {
        memoryFs.directory('/templates').createSync(recursive: true);
        memoryFs
            .file('/templates/welcome.html')
            .writeAsStringSync('<p>Hi {{name}} from {{appName}}</p>');

        final html = renderEmailTemplate(
          templateName: 'welcome',
          variables: {'name': 'Morgan'},
          appName: 'Zonai',
          emailTemplatesPath: '/templates',
        );

        expect(html, contains('Morgan'));
        expect(html, contains('Zonai'));
      });
    });

    test('refuses to read a file outside the templates dir', () {
      withFs(() {
        memoryFs.directory('/templates').createSync(recursive: true);
        memoryFs.directory('/secrets').createSync(recursive: true);
        memoryFs
            .file('/secrets/private.html')
            .writeAsStringSync('<p>not yours</p>');

        expect(
          () => renderEmailTemplate(
            templateName: '../secrets/private',
            variables: const {},
            appName: 'Zonai',
            emailTemplatesPath: '/templates',
          ),
          throwsA(isA<InvalidEmailTemplateNameException>()),
          reason:
              'traversal out of the templates dir must be refused, not '
              'quietly rewritten',
        );
      });
    });

    test('refuses an absolute path even though the file exists', () {
      withFs(() {
        memoryFs.directory('/templates').createSync(recursive: true);
        memoryFs.file('/elsewhere.html').writeAsStringSync('<p>nope</p>');

        expect(
          () => renderEmailTemplate(
            templateName: '/elsewhere',
            variables: const {},
            appName: 'Zonai',
            emailTemplatesPath: '/templates',
          ),
          throwsA(isA<InvalidEmailTemplateNameException>()),
        );
      });
    });
  });
}
