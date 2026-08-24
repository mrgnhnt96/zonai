import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/reset_password.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart'
    show PasswordResetReason;

import 'fake_zonai_db.dart';

Future<int> _run(Args args, {FakeZonaiDb? db}) {
  final fakeDb = db ?? newFakeZonaiDb();
  return runScoped(
    resetAdminPassword,
    values: {
      argsProvider.overrideWith(() => args),
      loggerProvider.overrideWith(() => Logger.print(level: .error)),
      settingsProvider.overrideWith(() => fakeSettings),
      zonaiDbProvider.overrideWith(
        () =>
            () => fakeDb,
      ),
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
      expect(db.resetAdminPasswordCall, (
        email: 'a@example.com',
        newPassword: 'new-pass',
      ));
    });

    group('the temporary-password default', () {
      /// These go through `Args.parse` on purpose. `--no-force-reset` parses
      /// to `force-reset: false`, not to a `no-force-reset` key, and a
      /// hand-built `Args(args: {...})` cannot tell the two apart -- which is
      /// exactly how `add.dart`'s `--no-verify` stayed broken.
      test('requires a new password after the reset, by default', () async {
        final db = newFakeZonaiDb()..adminPasswordTableResult = 'admins';

        final exitCode = await _run(
          Args.parse(['--email', 'a@example.com', '--password', 'temp-pass-1']),
          db: db,
        );

        expect(exitCode, 0);
        expect(db.resetAdminPasswordCall, (
          email: 'a@example.com',
          newPassword: 'temp-pass-1',
        ));
        expect(db.requirePasswordResetCalls, [
          (
            table: 'admins',
            email: 'a@example.com',
            reason: PasswordResetReason.temporaryPassword,
            byUserId: 'cli',
          ),
        ]);
      });

      test('--no-force-reset leaves the new password standing', () async {
        final db = newFakeZonaiDb();

        final exitCode = await _run(
          Args.parse([
            '--email',
            'a@example.com',
            '--password',
            'my-own-pass-1',
            '--no-force-reset',
          ]),
          db: db,
        );

        expect(exitCode, 0);
        expect(db.resetAdminPasswordCall, isNotNull);
        expect(db.requirePasswordResetCalls, isEmpty);
      });

      test(
        'does not require a reset when the password change failed',
        () async {
          // The inverse order would lock the account out of a credential that
          // still works, using the command meant to restore access.
          final db = newFakeZonaiDb()
            ..resetAdminPasswordError = StateError('nope');

          final exitCode = await _run(
            Args.parse([
              '--email',
              'a@example.com',
              '--password',
              'temp-pass-1',
            ]),
            db: db,
          );

          expect(exitCode, 1);
          expect(db.requirePasswordResetCalls, isEmpty);
        },
      );

      test('reports failure when the password landed but the requirement '
          'did not', () async {
        // Exiting 0 here would tell an operator responding to a leak that the
        // account was locked down when only its password had changed -- and
        // the old sessions would still be live.
        final db = newFakeZonaiDb()
          ..requirePasswordResetError = StateError('no password column');

        final exitCode = await _run(
          Args.parse(['--email', 'a@example.com', '--password', 'temp-pass-1']),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.resetAdminPasswordCall, isNotNull);
      });
    });

    test(
      'fails when the underlying reset throws (e.g. no such admin)',
      () async {
        final db = newFakeZonaiDb()
          ..resetAdminPasswordError = StateError(
            'No admin account with email "a@example.com" exists',
          );

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com', 'password': 'new-pass'}),
          db: db,
        );

        expect(exitCode, 1);
      },
    );
  });
}
