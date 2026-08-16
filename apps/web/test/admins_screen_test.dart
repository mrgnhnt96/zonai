import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_web/components/admins_screen.dart';
import 'package:zonai_web/utils/admin_members.dart';

/// Component tests for the Admins screen (`docs/admin-invite-design.md` §5 W2).
///
/// [AdminsPanel] is pure, so these pump it directly: no provider scope, no
/// server, no session. What is being pinned is the part a screenshot would not
/// tell you — which controls are disabled, and whether the reason is on the
/// page before anything is clicked.
///
/// Note on the disabled assertions: they read `button.disabled` rather than
/// clicking and expecting nothing to happen. In a browser a disabled button
/// emits no click event, but `tester.click` invokes the handler directly, so a
/// click-based test would fail even against a correctly disabled control and
/// pass against one that merely *looks* disabled.

final _now = DateTime.utc(2026, 8, 16, 12);

AdminMember _admin(String email) => AdminMember(email: email, label: email, row: {'email': email});

AdminMembers _members({required List<String> admins, List<PendingInvite> invites = const []}) {
  return AdminMembers(admins: [for (final email in admins) _admin(email)], invites: invites);
}

Component _panel({
  required AdminMembers members,
  String? signedInEmail,
  String inviteEmail = '',
  void Function(String email)? onInvite,
  void Function(PendingInvite invite)? onRevoke,
  void Function(AdminMember member)? onRemove,
  bool isLoading = false,
  String? loadError,
}) {
  return AdminsPanel(
    members: members,
    signedInEmail: signedInEmail,
    now: _now,
    inviteEmail: inviteEmail,
    isLoading: isLoading,
    loadError: loadError,
    onInviteEmailChanged: (_) {},
    onInvite: onInvite ?? (_) {},
    onRevoke: onRevoke ?? (_) {},
    onRemove: onRemove ?? (_) {},
  );
}

List<button> _buttonsLabelled(String text) {
  return [for (final element in find.componentWithText(button, text).evaluate()) element.component as button];
}

void main() {
  group('the roster', () {
    testComponents('lists current admins and pending invites together', (tester) async {
      // One screen, one round trip: `GET /admin/members` answers both lists
      // precisely so this page cannot paint half of itself.
      tester.pumpComponent(
        _panel(
          members: _members(
            admins: ['ada@example.com', 'grace@example.com'],
            invites: [
              PendingInvite(
                email: 'linus@example.com',
                expiresAt: _now.add(const Duration(days: 6)),
                invitedByEmail: 'ada@example.com',
              ),
            ],
          ),
          signedInEmail: 'ada@example.com',
        ),
      );

      expect(find.text('Current admins (2)'), findsOneComponent);
      expect(find.text('ada@example.com'), findsOneComponent);
      expect(find.text('grace@example.com'), findsOneComponent);

      expect(find.text('Pending invites (1)'), findsOneComponent);
      expect(find.text('linus@example.com'), findsOneComponent);
      // Pending is shown as pending, with how long the link has left.
      expect(find.textContaining('Pending — expires in 6 days'), findsOneComponent);
      expect(find.textContaining('invited by ada@example.com'), findsOneComponent);
    });

    testComponents('says when there is nothing pending rather than showing an empty box', (tester) async {
      tester.pumpComponent(_panel(members: _members(admins: ['ada@example.com', 'grace@example.com'])));

      expect(find.text('No pending invites.'), findsOneComponent);
      expect(_buttonsLabelled('Revoke'), isEmpty);
    });

    testComponents('surfaces a load failure instead of an empty roster', (tester) async {
      // An empty admins list and a failed request look identical on screen
      // otherwise -- and one of them means "nobody can sign in".
      tester.pumpComponent(_panel(members: AdminMembers.empty, loadError: 'Forbidden'));

      expect(find.text('Could not load admins'), findsOneComponent);
      expect(find.text('Forbidden'), findsOneComponent);
      expect(_buttonsLabelled('Send invite'), isEmpty);
    });
  });

  group('inviting', () {
    testComponents('hands the typed address to its caller', (tester) async {
      final invited = <String>[];
      tester.pumpComponent(AdminInviteForm(value: '  grace@example.com  ', onInput: (_) {}, onSubmit: invited.add));

      await tester.click(find.componentWithText(button, 'Send invite'));

      // Trimmed, because a trailing space pasted from an email client is not
      // a different address.
      expect(invited, ['grace@example.com']);
    });

    testComponents('cannot be submitted empty', (tester) async {
      tester.pumpComponent(AdminInviteForm(value: '   ', onInput: (_) {}, onSubmit: (_) {}));

      expect(_buttonsLabelled('Send invite').single.disabled, isTrue);
    });

    testComponents('says up front when the address already has an invite', (tester) async {
      tester.pumpComponent(
        _panel(
          members: _members(
            admins: ['ada@example.com'],
            invites: const [PendingInvite(email: 'linus@example.com')],
          ),
          inviteEmail: 'linus@example.com',
        ),
      );

      expect(find.textContaining('already has a pending invite'), findsOneComponent);
      // Still submittable: the server resends rather than duplicating, and
      // resending is a thing someone legitimately wants to do.
      expect(_buttonsLabelled('Send invite').single.disabled, isFalse);
    });
  });

  group('revoking', () {
    testComponents('hands the invite to its caller', (tester) async {
      final revoked = <String>[];
      tester.pumpComponent(
        _panel(
          members: _members(
            admins: ['ada@example.com', 'grace@example.com'],
            invites: [PendingInvite(email: 'linus@example.com', expiresAt: _now.add(const Duration(days: 2)))],
          ),
          signedInEmail: 'ada@example.com',
          onRevoke: (invite) => revoked.add(invite.email),
        ),
      );

      await tester.click(find.componentWithText(button, 'Revoke'));

      expect(revoked, ['linus@example.com']);
    });
  });

  group('removing (design §4 item 6)', () {
    testComponents('is refused for your own account, with the reason on the page', (tester) async {
      tester.pumpComponent(
        _panel(
          members: _members(admins: ['ada@example.com', 'grace@example.com']),
          signedInEmail: 'ada@example.com',
        ),
      );

      final removeButtons = _buttonsLabelled('Remove');
      expect(removeButtons, hasLength(2));
      // Exactly one of the two: yours. The other admin is removable.
      expect(removeButtons.where((control) => control.disabled), hasLength(1));
      expect(
        removeButtons.onlyWhere((control) => control.disabled).attributes?['title'],
        contains('your own account'),
      );

      // Not a hover-only explanation -- the reason is readable next to the
      // control, before anyone tries.
      expect(find.textContaining('Another admin has to remove you'), findsOneComponent);
    });

    testComponents('is refused for the last admin, with the reason on the page', (tester) async {
      tester.pumpComponent(
        _panel(
          members: _members(admins: ['grace@example.com']),
          signedInEmail: 'ada@example.com',
        ),
      );

      expect(_buttonsLabelled('Remove').single.disabled, isTrue);
      expect(find.textContaining('This is the only admin'), findsOneComponent);
      expect(find.textContaining('Invite someone else first'), findsOneComponent);
    });

    testComponents('hands a removable admin to its caller', (tester) async {
      final removed = <String?>[];
      tester.pumpComponent(
        _panel(
          members: _members(admins: ['ada@example.com', 'grace@example.com']),
          signedInEmail: 'ada@example.com',
          onRemove: (member) => removed.add(member.email),
        ),
      );

      // Both rows carry a control labelled 'Remove'; the second is the one
      // that is not you and therefore not disabled.
      await tester.click(find.componentWithText(button, 'Remove').at(1));

      expect(removed, ['grace@example.com']);
    });
  });
}

extension on Iterable<button> {
  /// The one element matching [test], asserting there is exactly one.
  button onlyWhere(bool Function(button candidate) test) => where(test).single;
}
