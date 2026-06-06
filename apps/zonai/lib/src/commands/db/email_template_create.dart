import '../../commands/dev/actions/init_email_templates.dart';
import '../../deps/args.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/settings.dart';

const _usage = '''
Usage: zonai db email template create <name>

Create a new email template from the built-in verify_email starter.

Options:
  -h, --help      Show help information
''';

Future<int> createEmailTemplate(List<String> path) async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  if (path.length != 1 || path.first.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  final name = path.first.replaceAll('.html', '');
  final file = fs.file(fs.path.join(settings.emailTemplatesPath, '$name.html'));

  if (file.existsSync()) {
    logger.error('Template already exists: ${file.path}');
    return 1;
  }

  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${initEmailTemplates['verify_email']!.trim()}\n');
  logger.info('Created template: ${file.path}');
  return 0;
}
