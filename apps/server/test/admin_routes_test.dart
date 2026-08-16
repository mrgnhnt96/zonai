import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/zonai_schema.dart' show Jwt, JwtId, UnknownId;
import 'package:zonai_server/src/handlers/admin_handler.dart';

import '../routes/controllers/admin_controller.dart';

/// Route-level tests for the admin-management HTTP surface
/// (`docs/admin-invite-design.md` §3, §4, §5 W1).
///
/// Two boundaries, chosen for what each can be wrong about on its own.
///
/// [AdminController] against a stub [AdminHandler]: which handler method a
/// route reaches, and with which arguments. That is where a `:email` path
/// parameter can be dropped, an `authorization` header can fail to be
/// forwarded, or `removeMember` can be wired to `revokeInvite`.
///
/// [mayActOnAdminTable] and [buildMembersBody] directly: the two decisions
/// `AdminHandler` makes without `zonaiDB`. Testing the refusal through the
/// stub would be a tautology — a stub that overrides every method never
/// reaches the check — so the check is a pure function and is tested as one.
///
/// What this does NOT cover: that revali routes a real HTTP request to these
/// methods at all (see `admin_invite_rate_limit_test.dart`, which reads the
/// generated route table), and that `_requireAdmin` calls
/// [mayActOnAdminTable] with the table `_adminTable()` actually resolved.
/// Both need the generated server or a live database.
void main() {
  group('who may act on the admin table', () {
    // Design §4 item 1. Every one of the four routes funnels through this.
    test('an absent or unparseable Bearer token may not', () {
      expect(mayActOnAdminTable(null, 'staff'), isFalse);
    });

    test('an authenticated NON-admin may not', () {
      expect(
        mayActOnAdminTable(_jwt(table: 'staff', isAdmin: false), 'staff'),
        isFalse,
      );
    });

    test('an admin for a DIFFERENT table may not', () {
      // The half of §4 item 1 that no e2e fixture in this repo can falsify:
      // its single auth table is entirely admin, so an admin JWT for some
      // other collection cannot exist there to be refused.
      //
      // `admin.isAdmin` is true here and it is not a lie -- this caller
      // really is an admin, of `contractors`. `_adminTable()` resolves only
      // the FIRST configured `AsAdmin` table, so without the table clause
      // this JWT would invite to, and remove admins from, `staff`.
      expect(
        mayActOnAdminTable(_jwt(table: 'contractors', isAdmin: true), 'staff'),
        isFalse,
      );
    });

    test('an admin for that table may', () {
      expect(
        mayActOnAdminTable(_jwt(table: 'staff', isAdmin: true), 'staff'),
        isTrue,
      );
    });

    test('the table comparison is exact, not a prefix or a fold', () {
      expect(
        mayActOnAdminTable(_jwt(table: 'staff2', isAdmin: true), 'staff'),
        isFalse,
      );
      expect(
        mayActOnAdminTable(_jwt(table: 'Staff', isAdmin: true), 'staff'),
        isFalse,
      );
    });
  });

  group('GET /admin/members body', () {
    test('carries current admins and pending invites together', () {
      // One round trip is the requirement: the dashboard's Admins screen
      // renders both lists and a second fetch would let it paint half a page.
      final body = buildMembersBody(
        admins: [
          {'id': 'u1', 'email': 'a@example.com'},
        ],
        invites: [
          {
            'email': 'b@example.com',
            'invitedAt': '2026-08-16T00:00:00.000',
            'expiresAt': '2026-08-23T00:00:00.000',
            'invitedByEmail': 'a@example.com',
          },
        ],
      );

      expect(body.keys, ['admins', 'invites']);
      expect(body['admins'], [
        {'id': 'u1', 'email': 'a@example.com'},
      ]);
    });

    test('every pending invite carries its expiry', () {
      // §5 W2: "pending invites with their expiry". A list without it cannot
      // tell a live invite from one the cleanup cron has not swept yet.
      final body = buildMembersBody(
        admins: const [],
        invites: [
          {'email': 'b@example.com', 'expiresAt': '2026-08-23T00:00:00.000'},
        ],
      );

      final invites = body['invites']! as List<Map<String, Object?>>;
      expect(invites.single['expiresAt'], '2026-08-23T00:00:00.000');
    });

    test('an invite row is allowlisted, not passed through', () {
      // Design §4 items 8 and 10. `listAdminInvites` builds its own maps
      // today, so none of these keys is present -- which is exactly why this
      // is worth pinning: the row underneath is `_auth_challenges`, whose
      // `secretHash` IS the invite token's hash, and widening that projection
      // later must not silently widen this response.
      final body = buildMembersBody(
        admins: const [],
        invites: [
          {
            'email': 'b@example.com',
            'invitedAt': '2026-08-16T00:00:00.000',
            'expiresAt': '2026-08-23T00:00:00.000',
            'invitedByEmail': 'a@example.com',
            'secretHash': 'deadbeef',
            'metadata': {'invitedBy': 'u1'},
            'target': 'b@example.com',
            'canConsume': true,
          },
        ],
      );

      final invites = body['invites']! as List<Map<String, Object?>>;
      expect(invites.single.keys, [
        'email',
        'invitedAt',
        'expiresAt',
        'invitedByEmail',
      ]);
      expect('${body['invites']}', isNot(contains('deadbeef')));
    });

    test('an empty roster is an empty list, not a missing key', () {
      final body = buildMembersBody(admins: const [], invites: const []);

      expect(body['admins'], isEmpty);
      expect(body['invites'], isEmpty);
    });
  });

  group('GET /admin/members', () {
    test('forwards the Authorization header to the handler', () {
      final handler = _StubAdminHandler();

      AdminController(
        adminHandler: handler,
      ).members(authorization: 'Bearer admin-jwt');

      expect(handler.memberCalls, ['Bearer admin-jwt']);
    });

    test('forwards an absent header rather than substituting one', () async {
      // The route must not paper over a missing token: the handler is where
      // the 403 is decided, and it can only decide it if it sees the absence.
      final handler = _StubAdminHandler();

      await AdminController(adminHandler: handler).members(authorization: null);

      expect(handler.memberCalls, [null]);
    });
  });

  group('POST /admin/invites', () {
    test(
      'reaches inviteAdmin with the body email and the caller token',
      () async {
        final handler = _StubAdminHandler();

        await AdminController(adminHandler: handler).invite(
          authorization: 'Bearer admin-jwt',
          body: const AdminInviteBody(email: 'new@example.com'),
        );

        expect(handler.inviteCalls, [
          (authorization: 'Bearer admin-jwt', email: 'new@example.com'),
        ]);
      },
    );

    test('the response never carries the raw invite token', () async {
      // Design §4 item 8. The token exists only in the email; `inviteAdmin`
      // returns the address, table, expiry and resend flag, and the route adds
      // nothing to that map.
      final handler = _StubAdminHandler();

      final result = await AdminController(adminHandler: handler).invite(
        authorization: 'Bearer admin-jwt',
        body: const AdminInviteBody(email: 'new@example.com'),
      );

      expect(result.keys, ['email', 'table', 'expiresAt', 'isResend']);
      expect(
        result.keys,
        isNot(anyElement(anyOf(contains('token'), contains('Token')))),
      );
    });

    test('an empty email is rejected before it reaches a route', () {
      // `inviteAdmin` would happily mint a challenge targeting "" and mail it
      // nowhere, leaving a pending invite nobody can accept or find.
      expect(
        () => AdminInviteBody.fromJson({'email': '   '}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AdminInviteBody.fromJson(const {}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a body carries no caller-named table', () {
      // The collection is resolved server-side. A `table` field here would be
      // the escalation `startAdminOAuth` exists to avoid: an `AsAdmin`
      // collection named by the request instead of by the schema.
      expect(const AdminInviteBody(email: 'a@example.com').toJson().keys, [
        'email',
      ]);
    });
  });

  group('DELETE /admin/invites/:email', () {
    test('passes the path parameter through as the address', () async {
      final handler = _StubAdminHandler();

      await AdminController(adminHandler: handler).revokeInvite(
        authorization: 'Bearer admin-jwt',
        // What `Uri.pathSegments` hands back for
        // `/admin/invites/a%2Bb%40example.com` -- percent-decoded, and with
        // the `+` intact, which a query parameter would have turned into a
        // space.
        email: 'a+b@example.com',
      );

      expect(handler.revokeCalls, [
        (authorization: 'Bearer admin-jwt', email: 'a+b@example.com'),
      ]);
    });

    test('does not reach removeMember', () async {
      final handler = _StubAdminHandler();

      await AdminController(
        adminHandler: handler,
      ).revokeInvite(authorization: 'Bearer admin-jwt', email: 'b@example.com');

      expect(handler.removeCalls, isEmpty);
    });
  });

  group('DELETE /admin/members/:email', () {
    test('reaches removeMember, never revokeInvite', () async {
      // Revoking is not removing: one clears a pending invite, the other
      // deletes a live admin row and revokes their sessions. Crossing them
      // would make "remove" a silent no-op on an account that keeps working.
      final handler = _StubAdminHandler();

      await AdminController(adminHandler: handler).removeMember(
        authorization: 'Bearer admin-jwt',
        email: 'gone@example.com',
      );

      expect(handler.removeCalls, [
        (authorization: 'Bearer admin-jwt', email: 'gone@example.com'),
      ]);
      expect(handler.revokeCalls, isEmpty);
    });
  });
}

Jwt _jwt({required String table, required bool isAdmin}) {
  return Jwt(
    userId: UnknownId('u1'),
    table: table,
    jwtId: JwtId('j1'),
    expiresAt: DateTime.utc(2030),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: null),
  );
}

typedef _InviteCall = ({String? authorization, String email});

/// Records what the controller asked for and answers with fixed values.
///
/// Extends the real [AdminHandler] rather than implementing an interface
/// because there is no interface -- and extending is what proves the
/// controller calls the methods it would call in production, not a parallel
/// set that drifted. Every method is overridden, so nothing here reaches
/// `zonaiDB`; the authorization check that a real call would hit first is
/// tested against [mayActOnAdminTable] above instead.
class _StubAdminHandler extends AdminHandler {
  _StubAdminHandler();

  final memberCalls = <String?>[];
  final inviteCalls = <_InviteCall>[];
  final revokeCalls = <_InviteCall>[];
  final removeCalls = <_InviteCall>[];

  @override
  Future<Map<String, Object?>> members(String? authorization) async {
    memberCalls.add(authorization);
    return buildMembersBody(admins: const [], invites: const []);
  }

  @override
  Future<Map<String, Object?>> invite({
    required String? authorization,
    required String email,
  }) async {
    inviteCalls.add((authorization: authorization, email: email));
    // The exact shape `ZonaiDb.inviteAdmin` returns.
    return {
      'email': email,
      'table': 'staff',
      'expiresAt': '2026-08-23T00:00:00.000',
      'isResend': false,
    };
  }

  @override
  Future<void> revokeInvite({
    required String? authorization,
    required String email,
  }) async {
    revokeCalls.add((authorization: authorization, email: email));
  }

  @override
  Future<Map<String, Object?>> removeMember({
    required String? authorization,
    required String email,
  }) async {
    removeCalls.add((authorization: authorization, email: email));
    return {'id': 'u2', 'email': email};
  }
}
