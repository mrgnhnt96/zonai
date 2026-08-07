import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/remove.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import 'fake_zonai_db.dart';

Future<int> _run(Args args, {FakeZonaiDb? db}) {
  final fakeDb = db ?? newFakeZonaiDb();
  return runScoped(
    removeAdmin,
    values: {
      argsProvider.overrideWith(() => args),
      loggerProvider.overrideWith(() => Logger.print(level: .error)),
      settingsProvider.overrideWith(() => fakeSettings),
      zonaiDbProvider.overrideWith(() => () => fakeDb),
    },
  );
}

void main() {
  group('removeAdmin', () {
    test('fails when --email is missing', () async {
      final exitCode = await _run(Args(args: {}));
      expect(exitCode, 1);
    });

    test('fails when --email is empty', () async {
      final exitCode = await _run(Args(args: {'email': ''}));
      expect(exitCode, 1);
    });

    test('calls ZonaiDb.removeAdmin with the given email and succeeds', () async {
      final db = newFakeZonaiDb();
      final exitCode = await _run(
        Args(args: {'email': 'a@example.com'}),
        db: db,
      );

      expect(exitCode, 0);
      expect(db.removeAdminCall, 'a@example.com');
    });

    test('fails when the underlying removal throws (e.g. no such admin)', () async {
      final db = newFakeZonaiDb()
        ..removeAdminError = StateError(
          'No admin account with email "a@example.com" exists',
        );

      final exitCode = await _run(
        Args(args: {'email': 'a@example.com'}),
        db: db,
      );

      expect(exitCode, 1);
    });
  });
}
