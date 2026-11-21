import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'zonai_cli.dart';

/// Finds the checked-in fixture project `e2e/<name>` at the repo root.
///
/// Tries the path from `apps/zonai` (where `dart test` normally runs) first,
/// then the path from the repo root.
Directory resolveFixture(String name) {
  var fixtureRoot = Directory(
    p.normalize(p.join(Directory.current.path, '..', '..', 'e2e', name)),
  );
  if (!fixtureRoot.existsSync()) {
    fixtureRoot = Directory(p.normalize('e2e/$name'));
  }
  expect(
    fixtureRoot.existsSync(),
    isTrue,
    reason: 'fixture missing at ${fixtureRoot.path}',
  );
  return fixtureRoot;
}

/// Copies a fixture project into [destination], leaving out the build state
/// (`.zonai*` and `.dart_tool`) a previous run may have left in the source.
void copyFixtureTree(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (relative.startsWith('.zonai') || relative == '.dart_tool') {
      continue;
    }
    final targetPath = p.join(destination.path, relative);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      entity.copySync(targetPath);
    }
  }
}

/// Rewrites a copied fixture's `pubspec.yaml` so its `zonai_schema` path
/// dependency points back into [repoRoot] from the temp directory.
///
/// [packageName] must be the fixture's own package name: its sources import
/// `package:<packageName>/...` by that literal name.
void rewriteFixturePubspec({
  required Directory projectRoot,
  required Directory repoRoot,
  required String packageName,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: $packageName
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');
}

/// Runs the zonai CLI in [projectRoot] and expects it to exit 0.
///
/// A fixture project depends only on `zonai_schema`, not `zonai` itself, so
/// it can't JIT-link a project-linked entry (`package:zonai/...` isn't
/// resolvable from it). Forcing the Mailman/IPC workers skips that
/// project-linked re-exec (see `maybeReexecProjectRuntime`) and drives
/// `db migrate generate`/`apply` through the already-compiled worker
/// executables instead.
Future<void> runZonaiInFixture(Directory projectRoot, List<String> args) async {
  final result = await runZonaiCli(
    args,
    workingDirectory: projectRoot.path,
    environment: const {'ZONAI_FORCE_WORKERS': '1'},
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}
