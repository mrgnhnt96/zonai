import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/reset_password.dart';
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
    resetAdminPassword,
    values: {
      argsProvider.overrideWith(() => args),
      loggerProvider.overrideWith(() => Logger.print(level: .error)),
      settingsProvider.overrideWith(() => fakeSettings),
      zonaiDbProvider.overrideWith(() => () => fakeDb),
    },
  );
}

void main() {
  group('resetAdminPassword', () {
    test('fails when --email is missing', () async {
      final exitCode = await _run(Args(args: {'password': 'new-pass'}));
      expect(exitCode, 1);
    });

    test('fails when --email is empty', () async {
      final exitCode = await _run(
        Args(args: {'email': '', 'password': 'new-pass'}),
      );
      expect(exitCode, 1);
    });

    test('fails when --password is missing', () async {
      final exitCode = await _run(Args(args: {'email': 'a@example.com'}));
      expect(exitCode, 1);
    });

    test('fails when --password is empty', () async {
      final exitCode = await _run(
        Args(args: {'email': 'a@example.com', 'password': ''}),
      );
      expect(exitCode, 1);
    });

    test('calls ZonaiDb.resetAdminPassword with the given email and password '
        'and succeeds', () async {
      final db = newFakeZonaiDb();
      final exitCode = await _run(
        Args(args: {'email': 'a@example.com', 'password': 'new-pass'}),
        db: db,
      );

      expect(exitCode, 0);
      expect(
        db.resetAdminPasswordCall,
        (email: 'a@example.com', newPassword: 'new-pass'),
      );
    });

    test('fails when the underlying reset throws (e.g. no such admin)', () async {
      final db = newFakeZonaiDb()
        ..resetAdminPasswordError = StateError(
          'No admin account with email "a@example.com" exists',
        );

      final exitCode = await _run(
        Args(args: {'email': 'a@example.com', 'password': 'new-pass'}),
        db: db,
      );

      expect(exitCode, 1);
    });
  });
}
