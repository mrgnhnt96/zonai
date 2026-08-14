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

/// Issue #25: SupposedlySam's review flagged that an omitted `where` on a
/// custom operation with non-empty `updates` skips row rules entirely,
/// letting the (documented-as-permissive) table rule alone authorize an
/// unbounded write across every row. `_customOperationBuild` rejects that
/// shape before any table/row rule dispatch, so this doesn't need a real
/// database, compiled workers, or registered rules to exercise.
void main() {
  test('custom() with non-empty updates and no where is rejected before any '
      'rule check runs', () async {
    await runScoped(
      () async {
        final db = ZonaiDb();
        try {
          await expectLater(
            db.custom(
              'tins',
              CustomPayload(
                operation: 'fill',
                updates: [Update.column('status', const Literal('filled'))],
              ),
            ),
            throwsA(isA<CustomOperationRequiresWhereException>()),
          );
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
  });

  test('custom() with no updates and no where (a table-scoped action) still '
      'reaches the table rule check', () async {
    await runScoped(
      () async {
        final db = ZonaiDb();
        try {
          await expectLater(
            db.custom('tins', const CustomPayload(operation: 'archive')),
            // Table rules aren't registered for "tins" in this fake setup,
            // so this reaches (and fails at) rule dispatch -- proving it
            // got past the where/updates guard, not blocked by it.
            throwsA(isNot(isA<CustomOperationRequiresWhereException>())),
          );
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
  });
}
