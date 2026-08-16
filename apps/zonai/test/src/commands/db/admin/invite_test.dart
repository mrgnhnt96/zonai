import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/invite.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import 'fake_zonai_db.dart';

/// `zonai db admin invite`, `invites` and `revoke-invite`
/// (`docs/admin-invite-design.md` §3.1).
///
/// These are the surface that makes the first admin invitable: `inviteAdmin`
/// wants an admin JWT, and before an admin exists there is none. The commands
/// therefore go through the `*FromCli` entry points, which take no session —
/// what these assert is that each command reaches the right one with the
/// right address, since calling the JWT-checked sibling would fail exactly
/// where it is needed most.
Future<int> _run(Future<int> Function() command, Args args, {FakeZonaiDb? db}) {
  final fakeDb = db ?? newFakeZonaiDb();
  return runScoped(
    command,
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
  group('inviteAdmin', () {
    test('fails when --email is missing', () async {
      final db = newFakeZonaiDb();
      final exitCode = await _run(inviteAdmin, Args(args: {}), db: db);

      expect(exitCode, 1);
      expect(
        db.inviteAdminFromCliCall,
        isNull,
        reason: 'a missing address must not reach the runtime as an empty one',
      );
    });

    test('fails when --email is empty', () async {
      final exitCode = await _run(inviteAdmin, Args(args: {'email': ''}));
      expect(exitCode, 1);
    });

    test('invites through the session-less entry point', () async {
      // The whole point of the command. `inviteAdmin` (JWT-checked) would
      // refuse here, because the case this exists for is "no admin yet".
      final db = newFakeZonaiDb()
        ..inviteAdminFromCliResult = const {
          'email': 'grace@example.com',
          'table': 'users',
          'expiresAt': '2026-01-08T00:00:00.000Z',
          'isResend': false,
        };

      final exitCode = await _run(
        inviteAdmin,
        Args(args: {'email': 'grace@example.com'}),
        db: db,
      );

      expect(exitCode, 0);
      expect(db.inviteAdminFromCliCall, 'grace@example.com');
    });

    test(
      'reports a failure as a non-zero exit rather than a sent invite',
      () async {
        final db = newFakeZonaiDb()
          ..inviteAdminFromCliError = StateError(
            'An admin account with email "grace@example.com" already exists',
          );

        final exitCode = await _run(
          inviteAdmin,
          Args(args: {'email': 'grace@example.com'}),
          db: db,
        );

        expect(exitCode, 1);
      },
    );
  });

  group('listAdminInvites', () {
    test('lists through the session-less entry point', () async {
      final db = newFakeZonaiDb()
        ..listAdminInvitesFromCliResult = const [
          {
            'email': 'grace@example.com',
            'invitedAt': '2026-01-01T00:00:00.000Z',
            'expiresAt': '2026-01-08T00:00:00.000Z',
            // Absent inviter: what a CLI-issued invite records, because there
            // is no user to attribute it to.
            'invitedByEmail': null,
          },
        ];

      final exitCode = await _run(listAdminInvites, Args(args: {}), db: db);

      expect(exitCode, 0);
      expect(db.listAdminInvitesFromCliCalled, isTrue);
    });

    test('an empty list is success, not failure', () async {
      // "Nobody is invited" is a real answer to the question, and an operator
      // scripting against this should not have to treat it as an error.
      final exitCode = await _run(listAdminInvites, Args(args: {}));
      expect(exitCode, 0);
    });
  });

  group('revokeAdminInvite', () {
    test('fails when --email is missing', () async {
      final db = newFakeZonaiDb();
      final exitCode = await _run(revokeAdminInvite, Args(args: {}), db: db);

      expect(exitCode, 1);
      expect(db.revokeAdminInviteFromCliCall, isNull);
    });

    test('revokes through the session-less entry point', () async {
      final db = newFakeZonaiDb();

      final exitCode = await _run(
        revokeAdminInvite,
        Args(args: {'email': 'grace@example.com'}),
        db: db,
      );

      expect(exitCode, 0);
      expect(db.revokeAdminInviteFromCliCall, 'grace@example.com');
    });

    test('succeeds for an address that had no invite', () async {
      // Deliberate: the runtime answers identically either way so that this
      // cannot be used to discover which addresses have invites pending, and
      // the command must not reintroduce that difference as an exit code.
      final exitCode = await _run(
        revokeAdminInvite,
        Args(args: {'email': 'never-invited@example.com'}),
      );

      expect(exitCode, 0);
    });
  });
}
