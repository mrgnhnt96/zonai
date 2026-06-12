// Generates lib/gen/swagger_assets.dart from public/swagger.{json,yaml}.
//
// Run from apps/server after revali generates swagger files:
//   dart run tool/generate_swagger_assets.dart
//
// Pass --check to exit 1 when generated files are out of date (for CI).
// Pass --stub to write placeholder constants before swagger files exist.

import 'dart:io';

const _sourceDir = 'public';
const _outputPath = 'lib/gen/swagger_assets.dart';

const _sources = {
  'kSwaggerJson': 'swagger.json',
  'kSwaggerYaml': 'swagger.yaml',
};

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final stubOnly = args.contains('--stub');
  final packageRoot = Directory.current.absolute;

  if (stubOnly) {
    _writeStub(File('${packageRoot.path}/$_outputPath'));
    stdout.writeln('Wrote stub ${packageRoot.path}/$_outputPath');
    return;
  }

  final contents = <String, String>{};
  for (final entry in _sources.entries) {
    final sourceFile = File('${packageRoot.path}/$_sourceDir/${entry.value}');
    if (!sourceFile.existsSync()) {
      stderr.writeln(
        '${sourceFile.path} is missing.\n'
        'Run: cd apps/server && dart run revali dev --generate-only --flavor dev',
      );
      exit(1);
    }
    contents[entry.key] = sourceFile.readAsStringSync();
  }

  final generated = _formatLibrary(contents);

  final outputFile = File('${packageRoot.path}/$_outputPath');
  if (checkOnly) {
    if (!outputFile.existsSync() || outputFile.readAsStringSync() != generated) {
      stderr.writeln(
        '${outputFile.path} is out of date. '
        'Run: dart run tool/generate_swagger_assets.dart',
      );
      exit(1);
    }
    stdout.writeln('${outputFile.path} is up to date.');
    return;
  }

  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(generated);
  stdout.writeln('Wrote ${outputFile.path}');
}

void _writeStub(File outputFile) {
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync('''
// GENERATED STUB - replaced by generate_swagger_assets.dart
library;

const kSwaggerJson = '{}';
const kSwaggerYaml = '';
''');
}

String _formatLibrary(Map<String, String> contents) {
  final buffer = StringBuffer('''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded OpenAPI specs for compiled Zonai builds.
//
// Regenerate:
//   dart run tool/generate_swagger_assets.dart

library;

''');

  for (final entry in contents.entries) {
    buffer.writeln('const ${entry.key} = ${_escapeRawString(entry.value)};');
    buffer.writeln();
  }

  return buffer.toString();
}

String _escapeRawString(String content) {
  if (!content.contains("'''")) {
    return "r'''$content'''";
  }

  final chunks = content.split("'''");
  final buffer = StringBuffer('(');
  for (var i = 0; i < chunks.length; i++) {
    if (i > 0) {
      buffer.write(" + \"'''\" + ");
    }
    buffer.write("r'''${chunks[i]}'''");
  }
  buffer.write(')');
  return buffer.toString();
}
