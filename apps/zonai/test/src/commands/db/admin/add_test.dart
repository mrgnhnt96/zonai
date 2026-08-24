import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/add.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart'
    show PasswordResetReason;
import 'package:zonai_schema/zonai_schema.dart' show AuthType;

import 'fake_zonai_db.dart';

Future<int> _run(Args args, {FakeZonaiDb? db}) {
  final fakeDb = db ?? newFakeZonaiDb();
  return runScoped(
    addAdmin,
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
  group('addAdmin', () {
    test('fails when --email is missing', () async {
      final exitCode = await _run(Args(args: {'password': 'pw'}));
      expect(exitCode, 1);
    });

    test('fails when --email is empty', () async {
      final exitCode = await _run(Args(args: {'email': '', 'password': 'pw'}));
      expect(exitCode, 1);
    });

    group('when the admin table supports password sign-in', () {
      test('fails when --password is missing', () async {
        final db = newFakeZonaiDb()
          ..adminTableResult = ('users', const [AuthType.password]);

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com'}),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.createAdminCall, isNull);
      });

      test('fails when --password is empty', () async {
        final db = newFakeZonaiDb()
          ..adminTableResult = ('users', const [AuthType.password]);

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com', 'password': ''}),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.createAdminCall, isNull);
      });

      test('creates the admin with the given password and succeeds', () async {
        final db = newFakeZonaiDb()
          ..adminTableResult = ('users', const [AuthType.password]);

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com', 'password': 'super-secret'}),
          db: db,
        );

        expect(exitCode, 0);
        expect(db.createAdminCall?.email, 'a@example.com');
        expect(db.createAdminCall?.password, 'super-secret');
      });
    });

    group('when the admin table has no password sign-in (OAuth-only)', () {
      test('succeeds without --password', () async {
        final db = newFakeZonaiDb()
          ..adminTableResult = ('admins', const [AuthType.oauth]);

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com'}),
          db: db,
        );

        expect(exitCode, 0);
        expect(db.createAdminCall?.email, 'a@example.com');
        expect(db.createAdminCall?.password, isNull);
      });

      test('fails with a clear error when --password is supplied', () async {
        final db = newFakeZonaiDb()
          ..adminTableResult = ('admins', const [AuthType.oauth]);

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com', 'password': 'super-secret'}),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.createAdminCall, isNull);
      });
    });

    /// Everything in this group goes through `Args.parse`.
    ///
    /// The rest of this file hand-builds `Args(args: {...})`, and that is how
    /// `--no-verify` was broken for as long as it was: `Args.parse` stores
    /// `--no-verify` as `verify: false`, never as `no-verify: true`, so the
    /// command's read of `'no-verify'` was null on every real invocation and
    /// `!= true` was always true. A hand-built map makes the broken read pass;
    /// only the parser can fail it.
    group('flags, through the real parser', () {
      test('--no-verify actually creates an unverified account', () async {
        final db = newFakeZonaiDb();

        final exitCode = await _run(
          Args.parse([
            '--email',
            'a@example.com',
            '--password',
            'super-secret',
            '--no-verify',
          ]),
          db: db,
        );

        expect(exitCode, 0);
        expect(db.createAdminCall?.verified, false);
      });

      test('an account is verified when --no-verify is absent', () async {
        final db = newFakeZonaiDb();

        await _run(
          Args.parse([
            '--email',
            'a@example.com',
            '--password',
            'super-secret',
          ]),
          db: db,
        );

        expect(db.createAdminCall?.verified, true);
      });

      test(
        '--force-reset requires a new password, after the account exists',
        () async {
          final db = newFakeZonaiDb()
            ..adminTableResult = ('admins', const [AuthType.password]);

          final exitCode = await _run(
            Args.parse([
              '--email',
              'a@example.com',
              '--password',
              'super-secret',
              '--force-reset',
            ]),
            db: db,
          );

          expect(exitCode, 0);
          expect(db.requirePasswordResetCalls, [
            (
              table: 'admins',
              email: 'a@example.com',
              reason: PasswordResetReason.temporaryPassword,
              byUserId: 'cli',
            ),
          ]);
        },
      );

      test('is opt-in: no requirement without --force-reset', () async {
        // Unlike `reset-password`. The person running `add` is frequently the
        // person who will sign in.
        final db = newFakeZonaiDb();

        await _run(
          Args.parse([
            '--email',
            'a@example.com',
            '--password',
            'super-secret',
          ]),
          db: db,
        );

        expect(db.requirePasswordResetCalls, isEmpty);
      });

      test('--force-reset is refused on an OAuth-only admin table, and the '
          'account is not created', () async {
        final db = newFakeZonaiDb()
          ..adminTableResult = ('admins', const [AuthType.oauth]);

        final exitCode = await _run(
          Args.parse(['--email', 'a@example.com', '--force-reset']),
          db: db,
        );

        expect(exitCode, 1);
        expect(db.createAdminCall, isNull);
        expect(db.requirePasswordResetCalls, isEmpty);
      });
    });

    test(
      'fails when the underlying create throws (e.g. duplicate email)',
      () async {
        final db = newFakeZonaiDb()
          ..createAdminError = StateError(
            'An account with email "a@example.com" already exists',
          );

        final exitCode = await _run(
          Args(args: {'email': 'a@example.com', 'password': 'super-secret'}),
          db: db,
        );

        expect(exitCode, 1);
      },
    );
  });
}
