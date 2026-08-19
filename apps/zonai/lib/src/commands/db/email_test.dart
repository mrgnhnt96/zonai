import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../../deps/args.dart';
import '../../deps/logger.dart';
import '../../deps/zonai_db.dart';
import '../../utils/email_template_variables.dart';

const _usage = '''
Usage: zonai db email test [options]

Send a test email using a built-in template.

Options:
  -h, --help              Show help information
  -t, --to <address>      Recipient email (required)
      --template <name>   Template name without .html (default: verify_email)
''';

Future<int> emailTest() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final to = args.getOrNull<String>('to', abbr: 't');
  if (to == null || to.isEmpty) {
    logger.error('--to is required');
    logger.info(_usage);
    return 1;
  }

  final template = args.getOrNull<String>('template') ?? 'verify_email';

  try {
    await zonaiDB.sendEmail(
      Email(
        to: EmailAddress(address: to, name: 'Test User'),
        subject: 'Zonai test email',
        template: template,
        preheader: samplePreheader,
        variables: {
          'name': 'Test User',
          'email': to,
          'verificationUrl': 'https://example.com/verify',
          'magicLinkUrl': 'https://example.com/magic',
          'passwordResetUrl': 'https://example.com/reset',
          'confirmChangeEmailUrl': 'https://example.com/confirm-email',
          'otp': '123456',
          'expiresIn': '1 hour',
          'currentEmail': to,
          'newEmail': 'new-$to',
          'signedInAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    logger.info('Test email sent to $to (template: $template)');
    return 0;
  } catch (e, stack) {
    logger.error('Failed to send test email: $e', e, stack);
    return 1;
  }
}
