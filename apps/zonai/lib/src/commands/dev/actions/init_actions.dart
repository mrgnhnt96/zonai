import 'dart:io';

import 'package:zonai/gen/version.dart';

import '../../../deps/args.dart';
import '../../../deps/fs.dart';
import '../../../deps/logger.dart';
import '../../../deps/process.dart';
import '../../../deps/settings.dart';
import '../../compile.dart';
import 'init_email_templates.dart';
import 'init_favicon.dart';
import 'init_scaffold.dart';

/// Scaffolds a new Zonai project: config, admin schema, email templates,
/// .gitignore entries, and worker compilation.
Future<void> initProject() async {
  _createPubspec();
  await _runPubGet();
  _createZonaiYaml();
  _updateGitignore();
  _createScaffold();
  await _compileWorkers();
}

void _createPubspec() {
  final file = fs.file('pubspec.yaml');
  if (file.existsSync()) return;

  final name = _deriveProjectName();
  file.writeAsStringSync('''name: $name
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema: ^$kVersion
''');
  stdout.writeln('Created pubspec.yaml');
}

String _deriveProjectName() {
  final dirName = fs.path.basename(fs.currentDirectory.path);
  var name = dirName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  if (name.isEmpty || !RegExp(r'^[a-z]').hasMatch(name)) {
    name = 'zonai_app';
  }
  return name;
}

Future<void> _runPubGet() async {
  if (!fs.file('pubspec.yaml').existsSync()) return;

  stdout.writeln('Running dart pub get...');
  final result = await process.runDart(['pub', 'get']);
  if (result.exitCode != 0) {
    logger.error('dart pub get failed');
    logger.error('${result.stderr}');
  }
}

void _createZonaiYaml() {
  final file = fs.file('zonai.yaml');
  if (file.existsSync()) return;

  file.writeAsStringSync('''
# Zonai configuration
version: $kVersion

migrationsPath: .zonai/migrations
schemasPath: lib/src/schemas
configPath: lib/src/config
emailTemplatesPath: lib/src/email_templates
rulesPath: lib/src/rules
operationsPath: lib/src/operations
extensionsPath: lib/src/extensions
rateLimitPath: lib/src/rate_limit
cronsPath: lib/src/crons
''');
  stdout.writeln('Created zonai.yaml');
}

void _updateGitignore() {
  const entries = ['*.stop', 'zonai.sqlite*', '.serve.lock'];

  final file = fs.file('.gitignore');
  final existing = file.existsSync() ? file.readAsStringSync() : '';
  final lines = existing.split('\n').toSet();
  final missing = entries.where((e) => !lines.contains(e)).toList();

  if (missing.isEmpty) return;

  final separator = existing.isNotEmpty && !existing.endsWith('\n') ? '\n' : '';
  file.writeAsStringSync(
    '$existing$separator${missing.join('\n')}\n',
    mode: FileMode.writeOnly,
  );
  stdout.writeln('Updated .gitignore: ${missing.join(', ')}');
}

void _createScaffold() {
  _writeIfAbsent('lib/src/ids.dart', initIdsDart);
  _writeIfAbsent('lib/src/schemas/admins.dart', initAdminsSchemaDart);
  _writeIfAbsent('lib/src/config/db_config.dart', initDbConfigDart);
  _writeIfAbsent(
    'lib/src/operations/admin_operations.dart',
    initAdminOperationsDart,
  );
  _writeIfAbsent('lib/src/rules/admin_table_rules.dart', initAdminRulesDart);

  for (final entry in initEmailTemplates.entries) {
    _writeIfAbsent(
      'lib/src/email_templates/${entry.key}.html',
      '${entry.value.trim()}\n',
    );
  }

  for (final dir in [
    '.zonai/migrations',
    'lib/src/extensions',
    'lib/src/rate_limit',
    'lib/src/crons',
  ]) {
    fs.directory(dir).createSync(recursive: true);
  }

  _writeBytesIfAbsent(
    fs.path.join(settings.imagesPath, 'favicon.ico'),
    kDefaultFavicon,
  );
}

void _writeIfAbsent(String path, String contents) {
  final file = fs.file(path);
  if (file.existsSync()) return;

  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  stdout.writeln('Created $path');
}

void _writeBytesIfAbsent(String path, List<int> bytes) {
  final file = fs.file(path);
  if (file.existsSync()) return;

  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  stdout.writeln('Created $path');
}

Future<void> _compileWorkers() async {
  if (args.release) {
    stdout.writeln('Skipping worker compile in release mode.');
    return;
  }

  stdout.writeln('Compiling workers...');
  final exitCode = await compile();
  if (exitCode != 0) {
    logger.warn('Worker compile finished with exit code $exitCode');
  }
}
