import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';

import 'package:zonai/src/internal/internal_db_artifacts.dart';

import '../../deps/fs.dart';
import '../../deps/settings.dart';
import '../../utils/schema_tables.dart';

/// Dropdown choices shared by dev TUI forms.
class DevFormOptions {
  const DevFormOptions({
    required this.emailTemplates,
    required this.cronJobNames,
    required this.schemaTables,
  });

  final List<String> emailTemplates;
  final List<String> cronJobNames;
  final List<SchemaTableInfo> schemaTables;
}

Future<DevFormOptions> loadDevFormOptions() async {
  final schemaTables = loadSchemaTables(settings.schemasPath);
  final templatesDir = fs.directory(settings.emailTemplatesPath);
  final emailTemplates = <String>[];
  if (templatesDir.existsSync()) {
    for (final entity in templatesDir.listSync()) {
      if (entity is! File) continue;
      final name = fs.path.basename(entity.path);
      if (name.endsWith('.html')) {
        emailTemplates.add(name.substring(0, name.length - 5));
      }
    }
    emailTemplates.sort();
  }

  final cronJobNames = await _loadCronJobNames();

  return DevFormOptions(
    emailTemplates: emailTemplates,
    cronJobNames: cronJobNames,
    schemaTables: schemaTables,
  );
}

final _cronNamePattern = RegExp(r'''name:\s*['"]([^'"]+)['"]''');

Future<List<String>> _loadCronJobNames() async {
  final names = <String>{};

  for (final entry in InternalDbArtifacts.crons) {
    final uri = await Isolate.resolvePackageUri(Uri.parse(entry.importPath));
    if (uri == null) continue;
    final name = _parseCronNameFromSource(
      io.File.fromUri(uri).readAsStringSync(),
    );
    if (name != null) names.add(name);
  }

  final cronsDir = fs.directory(settings.cronsPath);
  if (cronsDir.existsSync()) {
    for (final entity in cronsDir.listSync(recursive: true)) {
      if (entity is! File || fs.path.extension(entity.path) != '.dart') {
        continue;
      }
      final name = _parseCronNameFromSource(entity.readAsStringSync());
      if (name != null) names.add(name);
    }
  }

  return names.toList()..sort();
}

String? _parseCronNameFromSource(String source) {
  return _cronNamePattern.firstMatch(source)?.group(1);
}
