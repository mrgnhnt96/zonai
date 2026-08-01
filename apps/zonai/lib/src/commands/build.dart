import 'package:file/file.dart';
import 'package:zonai/src/commands/compile.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/migrate.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/project/project_binary.dart';

const _usage = '''
Usage: zonai build

Options:
  -h, --help      Show help information
''';

Future<int> build() async {
  if (args.help) {
    print(_usage);
    return 1;
  }

  if (fs.directory(settings.buildDirectory) case final dir
      when dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }

  logger.info('Building zonai artifacts');
  logger.debug('Building for ${settings.buildSettings}');

  if (await compile(settings.buildSettings) case final exitCode
      when exitCode != 0) {
    return exitCode;
  }

  // copy Email templates
  if (fs.directory(settings.emailTemplatesPath) case final dir
      when dir.existsSync()) {
    final emails = dir.listSync();
    if (emails.isNotEmpty) {
      fs
          .directory(settings.buildEmailTemplatesPath)
          .createSync(recursive: true);
    }

    for (final email in emails) {
      if (email is File) {
        fs
            .file(email.path)
            .copySync(
              fs.path.join(
                settings.buildEmailTemplatesPath,
                fs.path.basename(email.path),
              ),
            );
      }
    }
  }

  // copy SQL migrations
  final migrations = await migrate.migrations();
  String target;
  for (final migration in migrations) {
    target = fs.path.join(settings.buildMigrationsPath, '${migration.tag}.sql');
    final file = fs.file(target)..createSync(recursive: true);
    await file.writeAsString(migration.sql);
  }

  if (fs.file(settings.path) case final file when file.existsSync()) {
    file.copySync(settings.buildSettingsPath);
  }

  if (fs.file(fs.path.join(settings.imagesPath, 'favicon.ico')) case final file
      when file.existsSync()) {
    fs.directory(settings.buildImagesPath).createSync(recursive: true);
    file.copySync(fs.path.join(settings.buildImagesPath, 'favicon.ico'));
  }

  // Project-linked binary with in-process ops/rules (full CLI surface).
  if (await ProjectBinary().compile(buildSettings: settings.buildSettings)
      case final exitCode
      when exitCode != 0) {
    return exitCode;
  }

  return 0;
}
