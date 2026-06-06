import 'email_template_create.dart';
import 'email_test.dart';
import '../../deps/args.dart';
import '../../deps/logger.dart';

const _usage = '''
Usage: zonai db email <subcommand>

Subcommands:
  test                        Send a test email
  template create <name>      Create a starter email template

Options:
  -h, --help      Show help information
''';

Future<int> email(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['test']:
      return await emailTest();
    case ['template', 'create', ...final rest] when rest.isNotEmpty:
      return await createEmailTemplate(rest);
    default:
      logger.info(_usage);
      return 1;
  }
}
