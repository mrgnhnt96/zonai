import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zonai/src/domain/gen/client_package_exports.dart';
import 'package:zonai/src/domain/gen/client_runtime_source.dart';

/// `libs/zonai_client/lib/zonai_client.dart`, found by walking up from this
/// file rather than from the working directory.
///
/// `Platform.script` is the test runner, not this file, so the anchor is
/// [Directory.current] climbed until the repo root shows itself. A test whose
/// input depends on where it was invoked from is a test that passes for the
/// wrong reason somewhere.
File _clientBarrel() {
  var directory = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final candidate = File(
      p.join(
        directory.path,
        'libs',
        'zonai_client',
        'lib',
        'zonai_client.dart',
      ),
    );
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }

  // Deliberately a failure and not a skip. Three tests in `apps/docs` once
  // skipped silently when their input moved, and the drift they existed to
  // catch shipped. A check that cannot find its subject has not passed.
  fail(
    'Could not find libs/zonai_client/lib/zonai_client.dart above '
    '${Directory.current.path}. This test derives kZonaiClientExports from '
    'that file; it cannot run without it.',
  );
}

/// Every name a library's export directives contribute, resolved one level
/// deep: the `show` clauses, plus the public top-level declarations of each
/// unrestricted export target.
Set<String> _exportedNames(File barrel) {
  final source = barrel.readAsStringSync().replaceAll(RegExp('//[^\n]*'), '');
  final names = <String>{};

  for (final directive in RegExp(
    "export\\s+'([^']+)'([^;]*);",
    dotAll: true,
  ).allMatches(source)) {
    final show = RegExp(
      r'show\s+(.*)$',
      dotAll: true,
    ).firstMatch(directive.group(2)!);

    if (show != null) {
      names.addAll(
        show
            .group(1)!
            .split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty),
      );
      continue;
    }

    // An unrestricted export contributes everything the target declares.
    final target = File(p.join(p.dirname(barrel.path), directive.group(1)!));
    expect(
      target.existsSync(),
      isTrue,
      reason: '${directive.group(1)} is exported but not on disk',
    );
    final body = target.readAsStringSync().replaceAll(RegExp('//[^\n]*'), '');
    for (final declaration in RegExp(
      r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
      r'(?:class|mixin|enum|typedef|extension type)\s+(?:const\s+)?(\w+)',
      multiLine: true,
    ).allMatches(body)) {
      final name = declaration.group(1)!;
      if (!name.startsWith('_')) names.add(name);
    }
  }

  return names;
}

void main() {
  group('kZonaiClientExports', () {
    test('is exactly what zonai_client exports, in both directions', () {
      // Both directions on purpose. The first version of the equivalent check
      // for `kClientRuntimeExports` only caught a name in the source that was
      // missing from the list -- the mutation that proved the gap was adding
      // a name to the LIST that nothing declared, and it passed.
      final actual = _exportedNames(_clientBarrel());

      expect(
        actual.difference(kZonaiClientExports.toSet()),
        isEmpty,
        reason:
            'zonai_client exports these and kZonaiClientExports does not '
            'carry them, so the generated barrel would not hide a table that '
            'minted one -- an ambiguous export in the consumer project',
      );
      expect(
        kZonaiClientExports.toSet().difference(actual),
        isEmpty,
        reason:
            'kZonaiClientExports carries these and zonai_client no longer '
            'exports them, so a table minting one would be hidden from the '
            're-export for no reason',
      );
    });

    test('is sorted, because the hide clause is emitted in its order', () {
      expect(
        kZonaiClientExports,
        orderedEquals([...kZonaiClientExports]..sort()),
      );
    });

    test('does not overlap the generated runtime', () {
      // An overlap would be an ambiguous export in every generated barrel,
      // with no table involved at all: the runtime `show` clause and the
      // package re-export would both carry the name.
      expect(
        kZonaiClientExports.toSet().intersection(kClientRuntimeExports.toSet()),
        isEmpty,
      );
    });
  });
}
