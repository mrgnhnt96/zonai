import 'package:test/test.dart';
import 'package:zonai_web/utils/admin_members.dart';

/// The decisions the Admins screen makes about `GET /admin/members`, tested
/// where they are decisions rather than pixels (`docs/admin-invite-design.md`
/// §4 items 6 and 10).

AdminMember _member(String? email, {String? label}) {
  return AdminMember(email: email, label: label ?? email ?? 'Unnamed account', row: const {});
}

void main() {
  group('reading an admin row', () {
    test('takes the conventional column first', () {
      expect(adminEmailFromRow(const {'email': 'ada@example.com', 'name': 'Ada'}), 'ada@example.com');
    });

    test('falls back to a differently named address column', () {
      // A project is free to call it whatever it likes; nothing in the
      // response says which column is the address.
      expect(adminEmailFromRow(const {'id': 'usr_1', 'workEmail': 'grace@example.com'}), 'grace@example.com');
    });

    test('falls back to any value shaped like an address', () {
      expect(adminEmailFromRow(const {'id': 'usr_1', 'contact': 'linus@example.com'}), 'linus@example.com');
    });

    test('reports no address rather than guessing at one', () {
      // The alternative to answering null here is putting some other string
      // into a `DELETE /admin/members/:email` path.
      expect(adminEmailFromRow(const {'id': 'usr_1', 'name': 'Ada Lovelace'}), isNull);
      expect(adminEmailFromRow(const {'note': 'ping me @ada'}), isNull);
      expect(adminEmailFromRow(const {'handle': 'ada@localhost'}), isNull);
      expect(adminEmailFromRow(const {'both': 'a@b.com c@d.com'}), isNull);
    });

    test('a row with no address is still listed, under its id', () {
      final parsed = parseAdminMembers(const {
        'admins': [
          {'id': 'usr_7', 'name': 'Ada'},
        ],
        'invites': [],
      });

      expect(parsed.admins.single.email, isNull);
      expect(parsed.admins.single.label, 'usr_7');
    });
  });

  group('parsing the members body', () {
    test('reads both lists from the one response', () {
      final parsed = parseAdminMembers(const {
        'admins': [
          {'id': 'usr_1', 'email': 'ada@example.com'},
          {'id': 'usr_2', 'email': 'grace@example.com'},
        ],
        'invites': [
          {
            'email': 'linus@example.com',
            'invitedAt': '2026-08-10T09:00:00.000Z',
            'expiresAt': '2026-08-17T09:00:00.000Z',
            'invitedByEmail': 'ada@example.com',
          },
        ],
      });

      expect(parsed.admins.map((a) => a.email), ['ada@example.com', 'grace@example.com']);
      expect(parsed.invites.single.email, 'linus@example.com');
      expect(parsed.invites.single.expiresAt, DateTime.parse('2026-08-17T09:00:00.000Z'));
      expect(parsed.invites.single.invitedByEmail, 'ada@example.com');
    });

    test('survives a body with neither list', () {
      final parsed = parseAdminMembers(const {});
      expect(parsed.admins, isEmpty);
      expect(parsed.invites, isEmpty);
    });
  });

  group('the two refusals (design §4 item 6)', () {
    test('an admin who is not you, with others left, may be removed', () {
      expect(
        adminRemovalRefusal(member: _member('grace@example.com'), adminCount: 2, signedInEmail: 'ada@example.com'),
        isNull,
      );
    });

    test('you cannot remove yourself', () {
      final reason = adminRemovalRefusal(
        member: _member('ada@example.com'),
        adminCount: 3,
        signedInEmail: 'ada@example.com',
      );
      expect(reason, isNotNull);
      expect(reason, contains('your own account'));
    });

    test('the comparison ignores case and surrounding space', () {
      // `_inviteAdmin` lowercases before storing, and a JWT claim may not
      // have been through the same normalisation.
      expect(
        adminRemovalRefusal(member: _member('Ada@Example.com'), adminCount: 3, signedInEmail: ' ada@example.com '),
        isNotNull,
      );
    });

    test('the last admin cannot be removed, even by someone else', () {
      final reason = adminRemovalRefusal(
        member: _member('grace@example.com'),
        adminCount: 1,
        signedInEmail: 'ada@example.com',
      );
      expect(reason, isNotNull);
      expect(reason, contains('only admin'));
    });

    test('a lone admin removing themselves is told it is themselves', () {
      // Both refusals apply. `ZonaiDb.removeAdmin` checks self-removal before
      // the last-admin guard, so this reports the one the server would --
      // otherwise the disabled control and the 403 tell two different stories.
      final reason = adminRemovalRefusal(
        member: _member('ada@example.com'),
        adminCount: 1,
        signedInEmail: 'ada@example.com',
      );
      expect(reason, contains('your own account'));
    });

    test('an unaddressable row cannot be removed at all', () {
      final reason = adminRemovalRefusal(member: _member(null), adminCount: 4, signedInEmail: 'ada@example.com');
      expect(reason, contains('no email address'));
    });

    test('an unknown signed-in address disables nothing extra', () {
      // SSR has no session to read, so the answer must not be "refuse
      // everything" -- the roster is still readable, and the server refuses
      // self-removal on its own regardless of what this said.
      expect(adminRemovalRefusal(member: _member('ada@example.com'), adminCount: 2, signedInEmail: null), isNull);
    });
  });

  group('what the invite field already knows', () {
    final members = AdminMembers(
      admins: [_member('ada@example.com')],
      invites: const [PendingInvite(email: 'linus@example.com')],
    );

    test('says nothing about an address that is neither', () {
      expect(existingInviteNote(email: 'grace@example.com', members: members), isNull);
      expect(existingInviteNote(email: '  ', members: members), isNull);
    });

    test('names an address that is already an admin', () {
      expect(existingInviteNote(email: 'ADA@example.com', members: members), contains('already an admin'));
    });

    test('says a second invite replaces the first, which is what the server does', () {
      expect(existingInviteNote(email: 'linus@example.com', members: members), contains('cancels the old one'));
    });
  });

  group('invite expiry', () {
    final now = DateTime.utc(2026, 8, 16, 12);

    test('counts down in the largest unit that fits', () {
      expect(inviteExpiryLabel(now.add(const Duration(days: 6)), now: now), 'expires in 6 days');
      expect(inviteExpiryLabel(now.add(const Duration(days: 1)), now: now), 'expires in 1 day');
      expect(inviteExpiryLabel(now.add(const Duration(hours: 5)), now: now), 'expires in 5 hours');
      expect(inviteExpiryLabel(now.add(const Duration(minutes: 20)), now: now), 'expires in 20 minutes');
      expect(inviteExpiryLabel(now.add(const Duration(seconds: 30)), now: now), 'expires in 1 minute');
    });

    test('says so when the window has closed', () {
      expect(inviteExpiryLabel(now.subtract(const Duration(minutes: 1)), now: now), 'expired');
    });

    test('does not invent an expiry it was not given', () {
      expect(inviteExpiryLabel(null, now: now), 'no expiry recorded');
    });
  });
}
