// The boundary that keeps `push` server-side, enforced rather than described.
//
// `push` is authorized by provenance: the only way to enqueue a fan-out is
// developer-authored Dart in an extension hook or a cron job, relayed by the
// host's IPC handler. `PushCaller` says so at the call site, but it cannot
// enforce it — Dart's only hard boundary is library privacy, and the
// production call site lives in a different library of this same package, so
// `PushCaller.serverCode` has to be public and anything could pass it.
//
// This is the enforcement. It fails when a call site appears that is not on the
// list below, which turns "should an HTTP route be able to send a
// notification?" into a decision someone makes on purpose instead of an
// omission nobody notices.
//
// If you are here because this test failed: adding your file to `_allowed` is a
// legitimate outcome. What is not legitimate is adding a *request-reachable*
// caller without deciding who may reach it, because there is no longer an
// identity check underneath to catch it. An unauthenticated endpoint that
// enqueues a fan-out is a public send button.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Files permitted to call `ZonaiDb.enqueuePush`, relative to `apps/zonai`.
const _allowed = {
  // The IPC handler. The one production caller: it relays an
  // `EnqueuePushRequest`, which only an extension hook or cron job produces.
  'lib/src/db_mutator/mailman.dart',

  // The fan-out's own tests, which drive the entry point directly.
  'test/src/db_mutator/zonai_db/push_fanout_test.dart',
};

/// The declaration and the part file it delegates to — not call sites.
const _declarations = {
  'lib/src/db_mutator/zonai_db/zonai_db.dart',
  'lib/src/db_mutator/zonai_db/parts/push.dart',
};

/// This file names the method in its own prose, so it would match itself.
const _self = 'test/src/db_mutator/zonai_db/push_entry_point_test.dart';

void main() {
  test('the fan-out entry point is only reachable from the IPC handler', () {
    final root = _packageRoot();
    final callers = <String>{};

    // Built by concatenation so this test does not match its own source.
    final needle = 'enqueuePush${'('}';

    for (final file
        in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final relative = p.relative(file.path, from: root).replaceAll(r'\', '/');

      // Generated code is not hand-written and not a decision anyone made.
      if (p.split(relative).contains('gen')) continue;
      if (_declarations.contains(relative) || relative == _self) continue;

      if (file.readAsStringSync().contains(needle)) callers.add(relative);
    }

    expect(
      callers,
      _allowed,
      reason:
          'The set of callers of ZonaiDb.enqueuePush changed.\n'
          'Nothing but provenance authorizes a fan-out — PushCaller is a '
          'signpost, and this list is the boundary. A new caller reachable '
          'from an HTTP request needs its own decision about who may trigger '
          'it: read push_caller.dart, and /push/sending on the docs site for '
          'the amplification it hands out.',
    );
  });
}

/// `apps/zonai`, resolved through the package config the test runs under —
/// the same door `doc_snippets_test.dart` uses, because `Platform.script`
/// points at a generated bootstrap rather than at this file.
String _packageRoot() {
  final configFile = File(Uri.parse(Platform.packageConfig!).toFilePath());
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  for (final raw in config['packages'] as List<dynamic>) {
    final pkg = raw as Map<String, dynamic>;
    if (pkg['name'] != 'zonai') continue;
    return p.normalize(
      p.join(p.dirname(configFile.absolute.path), pkg['rootUri'] as String),
    );
  }

  throw StateError('Package "zonai" not found in ${Platform.packageConfig}');
}
