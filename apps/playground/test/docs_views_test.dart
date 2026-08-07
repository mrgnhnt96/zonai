import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _workspaceRoot() {
  final configUri = Platform.packageConfig!;
  final configFile = File(Uri.parse(configUri).toFilePath());
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  for (final raw in config['packages'] as List<dynamic>) {
    final pkg = raw as Map<String, dynamic>;
    if (pkg['name'] != 'zonai_workspace') continue;
    final rootUri = pkg['rootUri'] as String;
    return p.normalize(p.join(p.dirname(configFile.absolute.path), rootUri));
  }

  throw StateError('Package "zonai_workspace" not found in $configUri');
}

void main() {
  test(
    "docs/views.md doesn't reintroduce the raindrop import that collides "
    "with zonai_schema's vendored re-export",
    () {
      final docs = File(
        p.join(_workspaceRoot(), 'docs', 'views.md'),
      ).readAsStringSync();

      // zonai_schema.dart re-exports raindrop (hide table, Logger, migrate)
      // as of v0.5.2 -- importing package:raindrop/raindrop.dart alongside
      // it produces `ambiguous_import` for everything both export. The
      // real example this doc mirrors,
      // apps/playground/lib/src/operations/post_summary_operations.dart,
      // only imports zonai_schema for exactly this reason. See issue #22.
      expect(
        docs.contains("import 'package:raindrop/raindrop.dart'"),
        isFalse,
        reason:
            'docs/views.md should not tell readers to import raindrop '
            'alongside zonai_schema -- see apps/playground/lib/src/'
            'operations/post_summary_operations.dart for the pattern that '
            "actually compiles.",
      );
    },
  );
}
