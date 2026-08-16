import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/init_email_templates.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/email_template_render.dart';

void main() {
  group('initEmailTemplates admin_invite', () {
    test('is registered', () {
      expect(initEmailTemplates.containsKey('admin_invite'), isTrue);
    });

    test(
      'renders with no unsubstituted placeholders when invitedByEmail is known',
      () {
        final memoryFs = MemoryFileSystem();

        runScoped(() {
          memoryFs.directory('templates').createSync();
          memoryFs
              .file('templates/admin_invite.html')
              .writeAsStringSync(initEmailTemplates['admin_invite']!);

          final html = renderEmailTemplate(
            templateName: 'admin_invite',
            variables: {
              'inviteUrl': 'https://example.com/admin/invite?token=abc123',
              'email': 'new-admin@example.com',
              'expiresIn': '3 days',
              'invitedByEmail': 'owner@example.com',
            },
            appName: 'Test App',
            emailTemplatesPath: 'templates',
          );

          expect(html, isNot(contains('{{')));
          expect(html, contains('owner@example.com'));
          expect(html, contains('new-admin@example.com'));
          expect(html, contains('3 days'));
          // Mustache HTML-escapes the URL (e.g. "/" -> "&#x2F;"), same as the
          // other built-in templates; the token still round-trips intact.
          expect(html, contains('token=abc123'));
        }, values: {fsProvider.overrideWith(() => memoryFs)});
      },
    );

    test(
      'renders with no unsubstituted placeholders when invitedByEmail is absent',
      () {
        final memoryFs = MemoryFileSystem();

        runScoped(() {
          memoryFs.directory('templates').createSync();
          memoryFs
              .file('templates/admin_invite.html')
              .writeAsStringSync(initEmailTemplates['admin_invite']!);

          final html = renderEmailTemplate(
            templateName: 'admin_invite',
            variables: {
              'inviteUrl': 'https://example.com/admin/invite?token=abc123',
              'email': 'new-admin@example.com',
              'expiresIn': '3 days',
            },
            appName: 'Test App',
            emailTemplatesPath: 'templates',
          );

          expect(html, isNot(contains('{{')));
          expect(html, contains("You've been invited"));
        }, values: {fsProvider.overrideWith(() => memoryFs)});
      },
    );
  });
}
