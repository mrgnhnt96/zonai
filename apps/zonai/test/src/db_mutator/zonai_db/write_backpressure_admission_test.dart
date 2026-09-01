import 'dart:async';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/write_admission.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../../../support/temp_directory.dart';

/// Write backpressure at the [ZonaiDb] surface: every write entry point is
/// refused through the one gate, and a refused write is refused *before* the
/// scope that does its token check and Argon2 hash is ever opened.
///
/// The gate is filled through [ZonaiDb.writeAdmission] rather than with real
/// writes, so none of this needs a database or a compiled worker. The
/// [ZonaiDb] is never opened, and that absence is the proof: a `create` that
/// got past admission would fail with something else entirely -- the control
/// at the end of the first test shows exactly that.
///
/// Everything from filling the gate to releasing it happens in one
/// synchronous run (admission decides before its first `await`), so the real
/// 250ms expiry timers on the waiters never get a turn.
void main() {
  late io.Directory projectRoot;
  late Settings settings;

  setUp(() async {
    projectRoot = createCanonicalTempSync('zonai_write_admission_');
    io.File('${projectRoot.path}/zonai.yaml').writeAsStringSync('name: test\n');
    io.Directory(
      '${projectRoot.path}/.zonai/migrations',
    ).createSync(recursive: true);
    settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  });

  tearDown(() async {
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  /// The minimum a [ZonaiDb] needs to be constructed; nothing here opens it.
  Future<T> withScope<T>(Future<T> Function() body) => runMergedScopedFuture(
    body,
    override: {
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(
        () => Logger(
          level: .warning,
          stdout: io.IOSink(_NullSink()),
          stderr: io.IOSink(_NullSink()),
        ),
      ),
      settingsProvider.overrideWith(() => settings),
      processProvider,
      cleanUpProvider,
      executableStopProvider,
      migrateProvider,
    },
  );

  const payload = CreatePayload(object: {'name': 'stress-x'});

  /// Holds every slot and every waiter seat, and returns a function that
  /// hands them all back in order.
  ({WriteAdmission gate, Future<void> Function() drain}) fill(ZonaiDb db) {
    final gate = db.writeAdmission;
    final slots = <Future<WriteSlot>>[];
    final waiters = <Future<WriteSlot>>[];
    while (gate.admitted < 64) {
      slots.add(gate.admit());
    }
    while (gate.waiting < 64) {
      waiters.add(gate.admit());
    }
    return (
      gate: gate,
      drain: () async {
        // Each slot release is handed straight to a waiter; then the waiters
        // release theirs and the gate is empty again.
        for (final slot in await Future.wait(slots)) {
          slot.release();
        }
        for (final slot in await Future.wait(waiters)) {
          slot.release();
        }
      },
    );
  }

  test(
    'a create arriving past a full gate is refused before its scope opens',
    () => withScope(() async {
      final db = ZonaiDb();
      final (:gate, :drain) = fill(db);
      expect(gate.admitted, 64);
      expect(gate.waiting, 64);

      // Decided synchronously: the gate is full and every waiter seat is
      // taken, so this is the immediate refusal, not the window expiring.
      // (The expectation is attached before anything else awaits, so the
      // refusal is observed rather than surfacing as an unhandled error.)
      final refused = expectLater(
        db.create('items', payload),
        throwsA(isA<WriteBackpressureException>()),
      );
      expect(gate.waiting, 64, reason: 'it did not join the queue');

      await drain();
      expect(gate.admitted, 0);
      await refused;

      // Control: the same call with a free slot gets INTO the scope, where an
      // unopened database fails it with something that is not backpressure.
      // That is what shows the refusal above happened before that point --
      // before the token check, before the hasher.
      await expectLater(
        db.create('items', payload),
        throwsA(isNot(isA<WriteBackpressureException>())),
      );
      expect(
        gate.admitted,
        0,
        reason: 'the slot is released in `finally` on the failure path too',
      );
    }),
  );

  test(
    'a refused write carries an empty stack trace',
    () => withScope(() async {
      final db = ZonaiDb();
      final (:gate, :drain) = fill(db);

      Object? error;
      StackTrace? stack;
      final refused = db
          .create('items', payload)
          .then<void>(
            (_) {},
            onError: (Object e, StackTrace s) {
              error = e;
              stack = s;
            },
          );
      await drain();
      await refused;

      expect(error, isA<WriteBackpressureException>());
      // The 503 catcher's router logs every 5xx with its formatted trace; an
      // empty one is what keeps the reject path cheaper than the serve path.
      expect('$stack', isEmpty);
    }),
  );

  test(
    'update, delete, custom and createMany share the one gate',
    () => withScope(() async {
      final db = ZonaiDb();
      final (:gate, :drain) = fill(db);

      Future<void> refused(String name, Future<Object?> attempt) => expectLater(
        attempt,
        throwsA(isA<WriteBackpressureException>()),
        reason: '$name bypassed write admission',
      );
      final attempts = <Future<void>>[
        refused(
          'createMany',
          db.createMany(
            'items',
            const CreateManyPayload(
              objects: [
                {'name': 'a'},
              ],
            ),
          ),
        ),
        refused(
          'update',
          db.update(
            'items',
            UpdatePayload(
              where: const Eq('id', 1),
              updates: [
                Update.object(const {'name': 'b'}),
              ],
            ),
          ),
        ),
        refused(
          'delete',
          db.delete('items', const DeletePayload(where: Eq('id', 1))),
        ),
        refused(
          'custom',
          db.custom(
            'items',
            const CustomPayload(operation: 'touch', where: Eq('id', 1)),
          ),
        ),
      ];
      expect(gate.waiting, 64, reason: 'none of them joined the queue');
      await drain();
      await Future.wait(attempts);
    }),
  );

  test(
    'a waiter is admitted when a slot frees before the window',
    () => withScope(() async {
      final db = ZonaiDb();
      final gate = db.writeAdmission;
      final slots = <Future<WriteSlot>>[];
      while (gate.admitted < 64) {
        slots.add(gate.admit());
      }

      // 65th caller: full house, no one waiting -> it waits.
      final waiter = gate.admit();
      expect(gate.waiting, 1);

      // Free one slot well inside the window; it is handed to the waiter.
      (await slots.removeLast()).release();
      final granted = await waiter;
      expect(gate.waiting, 0);
      expect(gate.admitted, 64);

      granted.release();
      for (final slot in await Future.wait(slots)) {
        slot.release();
      }
      expect(gate.admitted, 0);
    }),
  );
}

class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
