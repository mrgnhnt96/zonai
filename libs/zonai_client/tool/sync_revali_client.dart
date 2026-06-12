// Copies the generated Revali HTTP client from apps/server/.revali into lib/gen/.
//
// Run from libs/zonai_client after server generation:
//   dart run tool/sync_revali_client.dart
//
// Pass --check to exit 1 when lib/gen is out of date (for CI).
// Pass --stub to write a placeholder entrypoint before server generation.

import 'dart:io';

const _sourceEnv = 'ZONAI_REVALI_CLIENT_SOURCE';
const _defaultSourceRelative = '../../apps/server/.revali/revali_client/lib';
const _outputRelative = 'lib/gen';
const _entrypoint = 'client.dart';

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final stubOnly = args.contains('--stub');
  final packageRoot = Directory.current.absolute;
  final outputDir = Directory('${packageRoot.path}/$_outputRelative').absolute;

  if (stubOnly) {
    _writeStub(outputDir);
    stdout.writeln('Wrote stub ${outputDir.path}/$_entrypoint');
    return;
  }

  final sourceDir = _resolveSourceDir(packageRoot, args);
  final entrypoint = File('${sourceDir.path}/$_entrypoint');

  if (!entrypoint.existsSync()) {
    stderr.writeln(
      '${entrypoint.path} is missing.\n'
      'Run: cd apps/server && dart run revali dev --generate-only --flavor dev',
    );
    exit(1);
  }

  if (checkOnly) {
    if (!_isUpToDate(sourceDir, outputDir)) {
      stderr.writeln(
        '${outputDir.path} is out of date. '
        'Run: dart run tool/sync_revali_client.dart',
      );
      exit(1);
    }
    stdout.writeln('${outputDir.path} is up to date.');
    return;
  }

  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }

  _copyDirectory(sourceDir, outputDir);

  final fileCount = _countFiles(outputDir);
  stdout.writeln('Wrote ${outputDir.path}');
  stdout.writeln('  $fileCount files from ${sourceDir.path}');
}

Directory _resolveSourceDir(Directory packageRoot, List<String> args) {
  final fromArg = _readArgValue(args, '--source');
  if (fromArg != null) {
    return Directory(fromArg).absolute;
  }

  final fromEnv = Platform.environment[_sourceEnv];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return Directory(fromEnv).absolute;
  }

  return Directory('${packageRoot.path}/$_defaultSourceRelative').absolute;
}

String? _readArgValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}

bool _isUpToDate(Directory sourceDir, Directory outputDir) {
  if (!File('${outputDir.path}/$_entrypoint').existsSync()) {
    return false;
  }

  final expectedPaths = <String>{};
  for (final entity in sourceDir.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }

    final relative = _relativePath(sourceDir.path, entity.path);
    expectedPaths.add(relative);

    final outputFile = File('${outputDir.path}/$relative');
    if (!outputFile.existsSync()) {
      return false;
    }

    if (!_bytesEqual(entity.readAsBytesSync(), outputFile.readAsBytesSync())) {
      return false;
    }
  }

  if (!outputDir.existsSync()) {
    return expectedPaths.isEmpty;
  }

  for (final entity in outputDir.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }

    final relative = _relativePath(outputDir.path, entity.path);
    if (!expectedPaths.contains(relative)) {
      return false;
    }
  }

  return true;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }

  return true;
}

void _copyDirectory(Directory sourceDir, Directory outputDir) {
  outputDir.createSync(recursive: true);

  for (final entity in sourceDir.listSync(recursive: true)) {
    final relative = _relativePath(sourceDir.path, entity.path);
    final targetPath = '${outputDir.path}/$relative';

    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
      continue;
    }

    if (entity is File) {
      final target = File(targetPath);
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
  }
}

int _countFiles(Directory directory) {
  var count = 0;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File) {
      count++;
    }
  }
  return count;
}

String _relativePath(String root, String path) {
  return Platform.pathSeparator == '/'
      ? path.substring(root.length + 1)
      : path.substring(root.length + 1).replaceAll(r'\', '/');
}

void _writeStub(Directory outputDir) {
  outputDir.createSync(recursive: true);
  File('${outputDir.path}/$_entrypoint').writeAsStringSync('''
// GENERATED STUB - replaced by sync_revali_client.dart
library;

/// Placeholder until Revali client generation runs.
///
/// Regenerate:
///   scripts zonai_client gen
///   (or) dart run tool/sync_revali_client.dart
class Client {
  Client({required String baseUrl, Client? client});
}
''');
}
