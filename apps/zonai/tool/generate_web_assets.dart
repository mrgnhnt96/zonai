// Generates lib/gen/web/web_assets.dart and part files from Jaspr build output.
//
// Run from apps/zonai after building the web app:
//   dart run tool/generate_web_assets.dart
//
// Pass --check to exit 1 when generated files are out of date (for CI).
// Pass --stub to write a placeholder web_assets.dart before `jaspr build`
// (the server compile step imports it before real assets exist).

import 'dart:convert';
import 'dart:io';

const _sourceEnv = 'JASPR_WEB_BUILD_DIR';
const _defaultSourceRelative = '../web/build/jaspr/web';
const _manifestName = '.build.manifest';
const _skipManifestEntries = {'.dart_tool/package_config.json'};

/// Matches [render_web_app.dart] static asset suffixes.
const _serveableSuffixes = {
  'css',
  'ico',
  'js',
  'json',
  'map',
  'png',
  'svg',
  'wasm',
};

/// Stale raw build output from earlier experiments; must not live under lib/.
const _orphanOutputDir = 'lib/gen/web_assets';

const _textExtensions = {
  'css',
  'html',
  'js',
  'json',
  'map',
  'md',
  'svg',
  'tpl',
  'txt',
  'yaml',
  'yml',
};

const _binaryExtensions = {'ico', 'png', 'wasm'};

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final stubOnly = args.contains('--stub');
  final packageRoot = Directory.current.absolute;
  final outputDir = Directory('${packageRoot.path}/lib/gen/web');

  if (stubOnly) {
    _writeStub(outputDir);
    stdout.writeln('Wrote stub ${outputDir.path}/web_assets.dart');
    return;
  }

  final sourceDir = _resolveSourceDir(packageRoot, args);
  final manifestFile = File('${sourceDir.path}/$_manifestName');
  if (!manifestFile.existsSync()) {
    stderr.writeln(
      '${manifestFile.path} is missing.\n'
      'Run: cd apps/web && dart run jaspr_cli:jaspr build',
    );
    exit(1);
  }

  final allManifestPaths =
      manifestFile
          .readAsLinesSync()
          .map((line) => line.trim())
          .where(
            (line) => line.isNotEmpty && !_skipManifestEntries.contains(line),
          )
          .toList()
        ..sort();

  final manifestPaths = allManifestPaths.where(_shouldEmbedAsset).toList();
  if (manifestPaths.isEmpty) {
    stderr.writeln(
      'No embeddable Jaspr web assets found in ${manifestFile.path}.\n'
      'Expected at least main.client.dart.js in ${sourceDir.path}.',
    );
    exit(1);
  }

  final generated = _generate(sourceDir, manifestPaths);

  if (checkOnly) {
    if (!_isUpToDate(outputDir, generated)) {
      stderr.writeln(
        '${outputDir.path} is out of date. '
        'Run: dart run tool/generate_web_assets.dart',
      );
      exit(1);
    }
    stdout.writeln('${outputDir.path} is up to date.');
    return;
  }

  _removeOrphanOutputDir(packageRoot);
  _replaceOutputDir(outputDir);

  for (final entry in generated.files.entries) {
    final file = File('${outputDir.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  stdout.writeln('Wrote ${generated.files.length} files to ${outputDir.path}');
  stdout.writeln(
    '  ${manifestPaths.length} embedded assets '
    '(${allManifestPaths.length - manifestPaths.length} manifest entries skipped)',
  );
}

/// Only embed browser-served Jaspr client assets, not the full build manifest.
bool _shouldEmbedAsset(String relativePath) {
  if (relativePath.startsWith('main.client.dart.js') &&
      relativePath.endsWith('.js')) {
    return true;
  }

  if (relativePath.contains('/')) {
    return false;
  }

  final suffix = relativePath.split('.').last.toLowerCase();
  return _serveableSuffixes.contains(suffix);
}

void _writeStub(Directory outputDir) {
  outputDir.createSync(recursive: true);
  File('${outputDir.path}/web_assets.dart').writeAsStringSync('''
// GENERATED STUB - replaced after `jaspr build` by generate_web_assets.dart
library;

class JasprWebAsset {
  const JasprWebAsset({required this.bytes, this.contentType});

  final List<int> bytes;
  final String? contentType;
}

JasprWebAsset? lookupJasprWebAsset(String relativePath) => null;
''');
}

void _removeOrphanOutputDir(Directory packageRoot) {
  final orphanDir = Directory('${packageRoot.path}/$_orphanOutputDir');
  if (orphanDir.existsSync()) {
    orphanDir.deleteSync(recursive: true);
    stdout.writeln('Removed stale ${orphanDir.path}');
  }
}

void _replaceOutputDir(Directory outputDir) {
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
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

bool _isUpToDate(Directory outputDir, _Generated generated) {
  for (final entry in generated.files.entries) {
    final file = File('${outputDir.path}/${entry.key}');
    if (!file.existsSync() || file.readAsStringSync() != entry.value) {
      return false;
    }
  }

  final expectedPaths = generated.files.keys.toSet();
  if (!outputDir.existsSync()) {
    return expectedPaths.isEmpty;
  }

  for (final entity in outputDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final relative = pRelative(outputDir.path, entity.path);
    if (!expectedPaths.contains(relative)) {
      return false;
    }
  }

  return true;
}

String pRelative(String from, String to) {
  return Platform.pathSeparator == '/'
      ? to.substring(from.length + 1)
      : to.substring(from.length + 1).replaceAll(r'\', '/');
}

class _Generated {
  _Generated(this.files);

  final Map<String, String> files;
}

class _AssetSpec {
  _AssetSpec({
    required this.relativePath,
    required this.partPath,
    required this.identifier,
    required this.isBinary,
    required this.contentType,
  });

  final String relativePath;
  final String partPath;
  final String identifier;
  final bool isBinary;
  final String? contentType;
}

_Generated _generate(Directory sourceDir, List<String> manifestPaths) {
  final files = <String, String>{};
  final specs = <_AssetSpec>[];

  for (final relativePath in manifestPaths) {
    final sourceFile = File('${sourceDir.path}/$relativePath');
    if (!sourceFile.existsSync()) {
      stderr.writeln('Missing asset listed in manifest: ${sourceFile.path}');
      exit(1);
    }

    final identifier = _pathToIdentifier(relativePath);
    final extension = relativePath.split('.').last.toLowerCase();
    final isBinary =
        _binaryExtensions.contains(extension) ||
        (!_textExtensions.contains(extension) && !_looksLikeText(sourceFile));

    specs.add(
      _AssetSpec(
        relativePath: relativePath,
        partPath: '$relativePath.dart',
        identifier: identifier,
        isBinary: isBinary,
        contentType: _contentTypeForAssetPath(relativePath),
      ),
    );

    final bytes = sourceFile.readAsBytesSync();
    files[specs.last.partPath] = isBinary
        ? _formatBinaryPart(identifier, bytes)
        : _formatTextPart(identifier, utf8.decode(bytes));
  }

  files['web_assets.dart'] = _formatMainLibrary(specs);
  return _Generated(files);
}

bool _looksLikeText(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.isEmpty) {
    return true;
  }

  final sample = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
  for (final byte in sample) {
    if (byte == 0) {
      return false;
    }
  }

  return true;
}

String _pathToIdentifier(String path) {
  final normalized = path.replaceAll(r'$', 'dollar');
  final parts = normalized
      .split(RegExp(r'[/._\-]+'))
      .where((part) => part.isNotEmpty);

  final buffer = StringBuffer();
  for (final part in parts) {
    if (part.isEmpty) {
      continue;
    }
    buffer
      ..write(part[0].toUpperCase())
      ..write(part.substring(1));
  }

  var identifier = buffer.toString();
  if (identifier.isEmpty) {
    identifier = 'asset';
  } else {
    identifier = identifier[0].toLowerCase() + identifier.substring(1);
  }

  if (RegExp(r'^\d').hasMatch(identifier)) {
    identifier = '_$identifier';
  }

  const reserved = {
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  if (reserved.contains(identifier)) {
    identifier = '${identifier}Asset';
  }

  return identifier;
}

String? _contentTypeForAssetPath(String path) {
  final suffix = path.split('.').last.toLowerCase();
  return switch (suffix) {
    'js' => 'application/javascript',
    'json' => 'application/json',
    'css' => 'text/css',
    'wasm' => 'application/wasm',
    'map' => 'application/json',
    'ico' => 'image/x-icon',
    'png' => 'image/png',
    'svg' => 'image/svg+xml',
    'html' => 'text/html; charset=utf-8',
    'txt' => 'text/plain; charset=utf-8',
    'md' => 'text/markdown; charset=utf-8',
    'yaml' || 'yml' => 'text/yaml; charset=utf-8',
    'tpl' => 'text/plain; charset=utf-8',
    _ => 'application/octet-stream',
  };
}

String _formatTextPart(String identifier, String content) {
  final body = _escapeRawString(content);
  return '''
part of 'package:zonai/gen/web/web_assets.dart';

const $identifier = $body;
''';
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

String _formatBinaryPart(String identifier, List<int> bytes) {
  final buffer = StringBuffer('''
part of 'package:zonai/gen/web/web_assets.dart';

const $identifier = <int>[
''');

  for (var i = 0; i < bytes.length; i++) {
    if (i % 16 == 0) {
      buffer.write('\n  ');
    }
    buffer.write('${bytes[i]},');
  }

  buffer.writeln('\n];');
  return buffer.toString();
}

String _formatMainLibrary(List<_AssetSpec> specs) {
  final needsConvert = specs.any((spec) => !spec.isBinary);
  final needsTypedData = specs.any((spec) => spec.isBinary);

  final buffer = StringBuffer('''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded Jaspr web assets for compiled Zonai builds.
//
// Regenerate:
//   scripts web gen
//   (or) dart run tool/generate_web_assets.dart

library;
''');

  if (needsConvert) {
    buffer.writeln("\nimport 'dart:convert';");
  }
  if (needsTypedData) {
    buffer.writeln("import 'dart:typed_data';");
  }
  buffer.writeln();

  for (final spec in specs) {
    buffer.writeln("part '${_escapeSingleQuoted(spec.partPath)}';");
  }

  buffer.writeln('''

class JasprWebAsset {
  const JasprWebAsset({required this.bytes, this.contentType});

  final List<int> bytes;
  final String? contentType;
}

final _jasprWebAssets = <String, JasprWebAsset>{
''');

  for (final spec in specs) {
    final contentTypeLiteral = spec.contentType == null
        ? 'null'
        : "'${spec.contentType}'";
    final bytesExpr = spec.isBinary
        ? 'Uint8List.fromList(${spec.identifier})'
        : 'utf8.encode(${spec.identifier})';
    buffer.writeln(
      "  '${_escapeSingleQuoted(spec.relativePath)}': JasprWebAsset(bytes: $bytesExpr, contentType: $contentTypeLiteral),",
    );
  }

  buffer.writeln('''
};

JasprWebAsset? lookupJasprWebAsset(String relativePath) =>
    _jasprWebAssets[relativePath];
''');

  return buffer.toString();
}

String _escapeSingleQuoted(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
}
