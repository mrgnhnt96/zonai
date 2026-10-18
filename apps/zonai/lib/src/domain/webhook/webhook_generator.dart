import 'package:file/file.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';

class WebhookGenerator {
  const WebhookGenerator({required this.webhooks});

  final List<File> webhooks;

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_webhooks.dart');

  Future<void> create() async {
    logger.debug('Starting webhook generator');

    final dartFiles = webhooks
        .where((f) => fs.path.extension(f.path) == '.dart')
        .toList();

    final root = fs.currentDirectory.path;
    final usedAliases = <String>{};
    final entries = <({String alias, String importPath})>[];

    final outDir = fs.directory(fs.path.join('.dart_tool', 'zonai'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final outDirAbsolute = outDir.absolute.path;

    final sorted = [...dartFiles]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in sorted) {
      final relativePosix = _relativePosixPath(file, root);
      final importPath = _relativePosixPath(file, outDirAbsolute);
      final alias = _uniqueAlias(relativePosix, usedAliases);
      entries.add((alias: alias, importPath: importPath));
    }

    fs.file(executablePath).writeAsStringSync(_source(entries));

    logger.debug('Generated webhook file: $executablePath');
    logger.debug('Used ${entries.length} webhook modules');
    for (final e in entries) {
      logger.debug('  - ${e.alias}: ${e.importPath}');
    }
  }

  String _relativePosixPath(File file, String root) {
    var relative = fs.path.relative(file.absolute.path, from: root);
    relative = fs.path.normalize(relative);
    return relative.replaceAll(r'\', '/');
  }

  String _uniqueAlias(String relativePosix, Set<String> used) {
    final segments = switch (fs.path.split(relativePosix)) {
      ['lib', ...final rest] => rest,
      final segments => segments,
    };
    final fileStem = fs.path.basenameWithoutExtension(segments.last);
    var candidate = fileStem;
    if (used.contains(candidate)) {
      final parents = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('_')
          : '';
      candidate = parents.isEmpty ? '${fileStem}_2' : '${parents}_$fileStem';
    }
    var n = 2;
    while (used.contains(candidate)) {
      candidate = '${fileStem}_$n';
      n++;
    }
    used.add(candidate);
    return candidate;
  }

  String _source(List<({String alias, String importPath})> entries) {
    final b = StringBuffer();
    b.writeln(
      "import 'package:zonai_schema/src/handlers/webhooks/db_webhooks.dart' "
      'as db_webhooks;',
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    for (final e in entries) {
      b.writeln("import '${e.importPath}' as ${e.alias};");
    }
    b.writeln();
    b.writeln('void main() {');
    b.writeln('  db_webhooks.DbWebhooks(');
    b.writeln('    webhooks: [');
    for (final e in entries) {
      b.writeln(
        '      loadWebhook(${_dartStringLiteral(e.importPath)}, ${e.alias}.main),',
      );
    }
    b.writeln('    ],');
    b.writeln('  ).start();');
    b.writeln('}');
    b.writeln();
    b.writeln(
      'Webhook loadWebhook(String sourcePath, Webhook Function() load) {',
    );
    b.writeln('  Object? value;');
    b.writeln('  try {');
    b.writeln('    value = load();');
    b.writeln('  } catch (e, st) {');
    b.writeln('    Error.throwWithStackTrace(StateError(');
    b.writeln(
      "      'Failed to load webhook from ' + sourcePath + ': "
      r'$e'
      "',",
    );
    b.writeln('    ), st);');
    b.writeln('  }');
    b.writeln('  if (value is! Webhook) {');
    b.writeln(
      '    final got = value == null ? "null" : value.runtimeType.toString();',
    );
    b.writeln('    throw StateError(');
    b.writeln(
      "      'Webhook file at ' + sourcePath + ' must return Webhook from main(); got "
      r'$got'
      ".',",
    );
    b.writeln('    );');
    b.writeln('  }');
    b.writeln('  return value;');
    b.writeln('}');
    return b.toString();
  }

  static String _dartStringLiteral(String s) =>
      "'${s.replaceAll('\\', '\\\\').replaceAll("'", r"\'")}'";
}
