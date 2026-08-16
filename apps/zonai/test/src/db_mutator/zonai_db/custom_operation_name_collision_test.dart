import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// A custom operation named after a classic verb is refused at the door.
///
/// `RuleRequest.classicOperation` resolves such a name to the built-in
/// operation, so `POST /db/:operation` with `operation: "update"` was
/// adjudicated by `canUpdate` — the classic table rule — while the author's
/// `customOperations['update']` entry, if any, went unread. On a table that
/// registered no such rule, the request then reached `TableOperations.custom`,
/// whose default throws `UnimplementedError`: a 500 for what is a caller naming
/// an operation that does not exist (N2).
///
/// `DbRules` refuses to *register* the collision; this refuses to *invoke* it,
/// which is what closes the shape above on tables that registered nothing.
/// Rejected before any rule dispatch, so it needs no database or workers.
void main() {
  Future<void> withDb(Future<void> Function(ZonaiDb db) body) async {
    await runScoped(
      () async {
        final db = ZonaiDb();
        try {
          await body(db);
        } finally {
          await db.dispose();
        }
      },
      values: {
        settingsProvider.overrideWith(() => fakeSettings),
        fsProvider.overrideWith(LocalFileSystem.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        cleanUpProvider,
        executableStopProvider,
      },
    );
  }

  // Every classic name, table-level and row-level. `count` and `list` exist
  // only as table operations, `create`/`view`/`update`/`delete` as both.
  for (final operation in const [
    'create',
    'update',
    'delete',
    'view',
    'list',
    'count',
  ]) {
    test('custom operation named "$operation" is refused', () async {
      await withDb((db) async {
        await expectLater(
          db.custom('tins', CustomPayload(operation: operation)),
          throwsA(
            isA<CustomOperationNameCollisionException>()
                .having((e) => e.operation, 'operation', operation)
                .having((e) => e.table, 'table', 'tins'),
          ),
        );
      });
    });
  }

  test('a custom operation with a name of its own is not caught by this '
      'guard', () async {
    await withDb((db) async {
      await expectLater(
        db.custom('tins', const CustomPayload(operation: 'archive')),
        // No rules are registered for "tins" here, so this goes on to fail at
        // rule dispatch -- which is the proof it got PAST the name guard
        // rather than being stopped by it.
        throwsA(isNot(isA<CustomOperationNameCollisionException>())),
      );
    });
  });
}
