import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/require_password_reset.dart';
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
    requireAdminPasswordReset,
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

/// The flags go through `Args.parse` rather than through `Args(args: {...})`.
///
/// Every other test in this directory hand-builds the map, which is how
/// `add.dart`'s `--no-verify` stayed broken: `Args.parse` stores `--no-x` as
/// `x: false`, not as `no-x: true`, so a command reading the `no-` key sees
/// null on every real invocation while a hand-built map makes it pass. A flag
/// test that skips the parser is testing the map, not the flag.
Args _cli(List<String> argv) => Args.parse(argv);

void main() {
  group('requireAdminPasswordReset', () {
    test('fails when --email is missing', () async {
      expect(await _run(_cli([])), 1);
    });

    test('fails when --email is empty', () async {
      expect(await _run(_cli(['--email='])), 1);
    });

    test('sets the requirement on the admin password table', () async {
      final db = newFakeZonaiDb()..adminPasswordTableResult = 'admins';

      final exitCode = await _run(_cli(['--email', 'a@example.com']), db: db);

      expect(exitCode, 0);
      expect(db.requirePasswordResetCalls, [
        (
          table: 'admins',
          email: 'a@example.com',
          reason: PasswordResetReason.adminForced,
          byUserId: 'cli',
        ),
      ]);
    });

    test('records the CLI as the setter, not a null admin', () async {
      // `created_by` is how an operator later answers "who locked this
      // account out". A null there is indistinguishable from a row written by
      // a code path that forgot to say.
      final db = newFakeZonaiDb();
      await _run(_cli(['-e', 'a@example.com']), db: db);

      expect(db.requirePasswordResetCalls.single.byUserId, 'cli');
    });

    group('--reason', () {
      test('accepts the kebab-case spelling of every enum value', () async {
        const cases = {
          'admin-forced': PasswordResetReason.adminForced,
          'compromised': PasswordResetReason.compromised,
          'temporary-password': PasswordResetReason.temporaryPassword,
          'password-policy': PasswordResetReason.passwordPolicy,
        };

        for (final MapEntry(key: spelling, value: expected) in cases.entries) {
          final db = newFakeZonaiDb();
          final exitCode = await _run(
            _cli(['--email', 'a@example.com', '--reason', spelling]),
            db: db,
          );

          expect(exitCode, 0, reason: spelling);
          expect(db.requirePasswordResetCalls.single.reason, expected);
        }
      });

      test('accepts the Dart identifier spelling too', () async {
        final db = newFakeZonaiDb();
        await _run(
          _cli(['--email', 'a@example.com', '--reason', 'temporaryPassword']),
          db: db,
        );

        expect(
          db.requirePasswordResetCalls.single.reason,
          PasswordResetReason.temporaryPassword,
        );
      });

      test('refuses an unknown value instead of falling back', () async {
        // Falling back to adminForced would write a row that says something
        // the operator did not, and the 403 would carry it to the client.
        final db = newFakeZonaiDb();
        final exitCode = await _run(
          _cli(['--email', 'a@example.com', '--reason', 'because-i-said-so']),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.requirePasswordResetCalls, isEmpty);
      });

      test('is refused alongside --clear rather than ignored', () async {
        final db = newFakeZonaiDb();
        final exitCode = await _run(
          _cli([
            '--email',
            'a@example.com',
            '--clear',
            '--reason',
            'compromised',
          ]),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.clearPasswordResetRequirementCalls, isEmpty);
        expect(db.requirePasswordResetCalls, isEmpty);
      });
    });

    group('--clear', () {
      test('clears instead of setting', () async {
        final db = newFakeZonaiDb()..adminPasswordTableResult = 'admins';

        final exitCode = await _run(
          _cli(['--email', 'a@example.com', '--clear']),
          db: db,
        );

        expect(exitCode, 0);
        expect(db.clearPasswordResetRequirementCalls, [
          (table: 'admins', email: 'a@example.com'),
        ]);
        expect(db.requirePasswordResetCalls, isEmpty);
      });

      test('succeeds when there was nothing to clear', () async {
        // The operator asked for "this account owes nothing", and that is the
        // state they get. Exiting 1 would make a script treat an
        // already-satisfied requirement as a failure.
        final db = newFakeZonaiDb()
          ..clearPasswordResetRequirementResult = false;

        expect(
          await _run(_cli(['--email', 'a@example.com', '--clear']), db: db),
          0,
        );
      });
    });

    test('fails when the account does not exist', () async {
      final db = newFakeZonaiDb()
        ..requirePasswordResetError = StateError(
          'No account with email "a@example.com" exists in "admins"',
        );

      expect(await _run(_cli(['--email', 'a@example.com']), db: db), 1);
    });

    test('fails when the admin table has no password column', () async {
      // A requirement there is unenforceable by construction, and an operator
      // who got a success would believe an OAuth-only account was constrained.
      final db = newFakeZonaiDb()
        ..requirePasswordResetError = StateError(
          '"admins" has no password column, so a password reset cannot be '
          'required of it',
        );

      expect(await _run(_cli(['--email', 'a@example.com']), db: db), 1);
    });

    test('fails when no admin password table is configured', () async {
      final db = newFakeZonaiDb()
        ..adminPasswordTableError = StateError('No AsAdmin password table');

      expect(await _run(_cli(['--email', 'a@example.com']), db: db), 1);
      expect(db.requirePasswordResetCalls, isEmpty);
    });
  });
}
