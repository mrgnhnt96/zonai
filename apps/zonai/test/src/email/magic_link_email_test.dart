import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/init_email_templates.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/email/magic_link_email.dart';
import 'package:zonai/src/utils/email_template_render.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show AuthOperation;
import 'package:zonai_schema/zonai_schema.dart' hide logger;

void main() {
  group(magicLinkEmail, () {
    late MemoryFileSystem memoryFs;

    setUp(() {
      memoryFs = MemoryFileSystem();
      memoryFs.directory('templates').createSync();
      memoryFs.file('templates/magic_link.html').writeAsStringSync('in');
    });

    void addSignUpTemplate() => memoryFs
        .file('templates/magic_link_sign_up.html')
        .writeAsStringSync('up');

    Email send(AuthOperation operation, {bool isResend = false}) => runScoped(
      () => magicLinkEmail(
        operation: operation,
        appName: 'Picto',
        to: const EmailAddress(address: 'New@Example.com'),
        table: 'users',
        isResend: isResend,
        magicLinkUrl: 'https://example.com/auth/magic-link?s=abc',
        expiresIn: const Duration(minutes: 15),
        variables: {'name': 'Ada', 'pending_invite_token': 'tok'},
        emailTemplatesPath: 'templates',
      ),
      values: {fsProvider.overrideWith(() => memoryFs)},
    );

    const variables = {
      'name': 'Ada',
      'pending_invite_token': 'tok',
      'magicLinkUrl': 'https://example.com/auth/magic-link?s=abc',
      'email': 'New@Example.com',
      'expiresIn': '15 minutes',
    };

    test('a sign-up uses the sign-up template when the app has it', () {
      addSignUpTemplate();

      final email = send(.signUp);

      expect(email, isA<MagicLinkSignUpEmail>());
      expect(email.template, 'magic_link_sign_up');
      expect(email.subject, 'Create your Picto account');
      expect(
        email.preheader,
        'Your link to create your account expires in 15 minutes.',
      );
      expect(email.to.address, 'New@Example.com');
      expect(email.variables, variables);
      expect(email.thread, 'magic-link:users:new@example.com');
    });

    test('a sign-up resend continues the same thread', () {
      addSignUpTemplate();

      expect(
        send(.signUp, isResend: true).thread,
        'magic-link:users:new@example.com${Email.continueThreadSuffix}',
      );
    });

    test('a sign-up without the template gets the sign-in email', () {
      final email = send(.signUp);

      expect(email, isA<SendMagicLinkEmail>());
      expect(email.template, 'magic_link');
      expect(email.subject, 'Sign in');
      expect(email.preheader, 'Your sign-in link expires in 15 minutes.');
      expect(email.variables, variables);
      expect(email.thread, 'magic-link:users:new@example.com');
    });

    test('a sign-in gets the sign-in email even when the sign-up template '
        'exists', () {
      addSignUpTemplate();

      final email = send(.signIn);

      expect(email, isA<SendMagicLinkEmail>());
      expect(email.template, 'magic_link');
      expect(email.subject, 'Sign in');
      expect(email.preheader, 'Your sign-in link expires in 15 minutes.');
      expect(email.variables, variables);
    });
  });

  group('emailTemplateExists', () {
    test('finds a template file and misses an absent one', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.directory('templates').createSync();
      memoryFs.file('templates/otp_code.html').writeAsStringSync('x');

      runScoped(() {
        expect(
          emailTemplateExists('otp_code', emailTemplatesPath: 'templates'),
          isTrue,
        );
        expect(
          emailTemplateExists('nope', emailTemplatesPath: 'templates'),
          isFalse,
        );
        expect(
          emailTemplateExists('../otp_code', emailTemplatesPath: 'templates'),
          isFalse,
        );
      }, values: {fsProvider.overrideWith(() => memoryFs)});
    });
  });

  group('built-in magic_link_sign_up template', () {
    test('renders a "create your account" link', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.directory('templates').createSync();
      memoryFs
          .file('templates/magic_link_sign_up.html')
          .writeAsStringSync(initEmailTemplates[kMagicLinkSignUpTemplate]!);

      final html = runScoped(
        () => renderEmailTemplate(
          templateName: kMagicLinkSignUpTemplate,
          variables: {
            'magicLinkUrl': 'https://example.com/auth/magic-link?s=abc',
            'email': 'new@example.com',
            'expiresIn': '10 minutes',
            'name': 'Ada',
          },
          appName: 'Picto',
          emailTemplatesPath: 'templates',
          preheader: 'Your link to create your account expires in 10 minutes.',
        ),
        values: {fsProvider.overrideWith(() => memoryFs)},
      );

      expect(html, isNot(contains('{{')));
      expect(html, contains('Hi Ada,'));
      expect(html, contains('Create your Picto account'));
      expect(html, contains('magic-link?s=abc'));
      expect(html, contains('10 minutes'));
    });
  });
}
