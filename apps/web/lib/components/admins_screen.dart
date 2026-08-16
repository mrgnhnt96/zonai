import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../constants/button_sizes.dart';
import '../providers/admin_members_provider.dart';
import '../providers/home_ui_provider.dart';
import '../utils/admin_members.dart';
import '../utils/user_facing_error.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/zonai_button.dart';
import 'theme/zonai_icon_button.dart';
import 'theme/zonai_text_field.dart';
import 'toast_overlay.dart';

/// The Admins screen (`docs/admin-invite-design.md` §5 W2): who can sign in to
/// this dashboard, who has been invited and not yet accepted, and the controls
/// to change both.
///
/// The screen splits in two on purpose. [AdminsScreen] is the wired half —
/// sidebar, providers, the text the user is currently typing. [AdminsPanel]
/// below it is pure: given a roster and three callbacks it renders the whole
/// page and decides nothing it was not handed. That is what lets a test pin
/// the part that matters most here — *which* controls are disabled and what
/// they say — without a server, a session, or a browser.
class AdminsScreen extends StatefulComponent {
  const AdminsScreen({super.key});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  String _inviteEmail = '';

  /// Addresses with an action in flight, so a second click cannot fire the
  /// same revoke or removal twice while the first is still travelling.
  final _busy = <String>{};

  @override
  Component build(BuildContext context) {
    final mobileNavOpen = context.watch(homeUiProvider).mobileNavOpen;
    final isClient = context.binding.isClient;

    // Same reason `DashboardScreen` guards its async providers: the roster is
    // fetched with the caller's bearer token, which SSR does not have, and a
    // provider that resolves after the server render has no frame to land in.
    final members = isClient ? context.watch(adminMembersProvider) : const AsyncValue<AdminMembers>.loading();
    final signedInEmail = context.watch(signedInAdminEmailProvider);

    return main_(classes: 'home${mobileNavOpen ? ' home--mobile-nav-open' : ''}', [
      HomeSidebar(focused: null),
      div(classes: 'home-main', [
        div(classes: 'home-mobile-nav-header', [
          ZonaiIconButton(
            size: ZonaiIconButtonSize.lg,
            attributes: {'aria-label': 'Open navigation', 'aria-expanded': mobileNavOpen ? 'true' : 'false'},
            onClick: () => context.read(homeUiProvider.notifier).toggleMobileNav(),
            child: .text('☰'),
          ),
          h1(classes: 'home-mobile-nav-title', [.text('Admins')]),
        ]),
        div(classes: 'dashboard-scroller', [
          div(classes: 'dashboard', [
            AdminsPanel(
              members: members.value ?? AdminMembers.empty,
              signedInEmail: signedInEmail,
              now: DateTime.now(),
              isLoading: members.isLoading && !members.hasValue,
              loadError: members.hasError ? userFacingError(members.error!) : null,
              inviteEmail: _inviteEmail,
              busyEmails: _busy,
              onInviteEmailChanged: (value) => setState(() => _inviteEmail = value),
              onInvite: _invite,
              onRevoke: (invite) =>
                  _run(invite.email, () => context.read(adminMembersProvider.notifier).revoke(invite.email)),
              onRemove: (member) {
                final email = member.email;
                if (email == null) return;
                _run(email, () => context.read(adminMembersProvider.notifier).remove(email));
              },
            ),
          ]),
        ]),
      ]),
      if (mobileNavOpen)
        div(
          classes: 'home-mobile-backdrop',
          attributes: {'aria-hidden': 'true'},
          events: {'click': (_) => context.read(homeUiProvider.notifier).closeMobileNav()},
          [],
        ),
      const HomeSettingsOverlay(),
      if (isClient) const ToastOverlay(),
    ]);
  }

  Future<void> _invite(String email) async {
    if (_busy.contains(email)) return;
    setState(() => _busy.add(email));
    try {
      final sent = await context.read(adminMembersProvider.notifier).invite(email);
      if (!mounted) return;
      if (sent) {
        setState(() => _inviteEmail = '');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(email));
    }
  }

  Future<void> _run(String email, Future<void> Function() action) async {
    if (_busy.contains(email)) return;
    setState(() => _busy.add(email));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(email));
    }
  }
}

/// Everything the Admins screen draws, as a function of what it is given.
class AdminsPanel extends StatelessComponent {
  const AdminsPanel({
    super.key,
    required this.members,
    required this.signedInEmail,
    required this.now,
    required this.inviteEmail,
    required this.onInviteEmailChanged,
    required this.onInvite,
    required this.onRevoke,
    required this.onRemove,
    this.isLoading = false,
    this.loadError,
    this.busyEmails = const {},
  });

  final AdminMembers members;

  /// The signed-in admin's own address, or null when it is not known (SSR).
  /// Only ever used to *disable* a control, so not knowing it costs a
  /// disabled button, never an unguarded one — the server refuses self-removal
  /// regardless.
  final String? signedInEmail;

  final DateTime now;
  final String inviteEmail;
  final void Function(String value) onInviteEmailChanged;
  final void Function(String email) onInvite;
  final void Function(PendingInvite invite) onRevoke;
  final void Function(AdminMember member) onRemove;
  final bool isLoading;
  final String? loadError;
  final Set<String> busyEmails;

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      div(classes: 'dashboard-header', [
        h1(classes: 'dashboard-title', [.text('Admins')]),
      ]),
      if (loadError case final error?)
        div(classes: 'dashboard-panel', [
          p(classes: 'dashboard-panel-title', [.text('Could not load admins')]),
          pre(classes: 'z-alert__body', [.text(error)]),
        ])
      else
        div(classes: 'dashboard-row dashboard-row--split', [
          div(classes: 'dashboard-panel z-admins-panel', [
            p(classes: 'dashboard-panel-title', [
              .text(members.admins.isEmpty ? 'Current admins' : 'Current admins (${members.admins.length})'),
            ]),
            if (isLoading && members.admins.isEmpty)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
            else if (members.admins.isEmpty)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
                .text('No admin accounts found.'),
              ])
            else
              div(classes: 'z-admins-list', [
                for (final member in members.admins)
                  _AdminRow(
                    member: member,
                    refusal: adminRemovalRefusal(
                      member: member,
                      adminCount: members.admins.length,
                      signedInEmail: signedInEmail,
                    ),
                    busy: member.email != null && busyEmails.contains(member.email),
                    onRemove: () => onRemove(member),
                  ),
              ]),
          ]),
          div(classes: 'dashboard-panel z-admins-panel', [
            p(classes: 'dashboard-panel-title', [
              .text(members.invites.isEmpty ? 'Pending invites' : 'Pending invites (${members.invites.length})'),
            ]),
            AdminInviteForm(
              value: inviteEmail,
              note: existingInviteNote(email: inviteEmail, members: members),
              pending: busyEmails.contains(inviteEmail.trim()),
              onInput: onInviteEmailChanged,
              onSubmit: onInvite,
            ),
            if (isLoading && members.invites.isEmpty)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
            else if (members.invites.isEmpty)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
                .text('No pending invites.'),
              ])
            else
              div(classes: 'z-admins-list', [
                for (final invite in members.invites)
                  _InviteRow(
                    invite: invite,
                    now: now,
                    busy: busyEmails.contains(invite.email),
                    onRevoke: () => onRevoke(invite),
                  ),
              ]),
          ]),
        ]),
    ]);
  }
}

/// The invite field and its button.
///
/// Controlled — it holds no text of its own — so the screen above owns the
/// value and a test can pump this with an address already in it and click.
class AdminInviteForm extends StatelessComponent {
  const AdminInviteForm({
    super.key,
    required this.value,
    required this.onInput,
    required this.onSubmit,
    this.note,
    this.pending = false,
  });

  final String value;
  final void Function(String value) onInput;
  final void Function(String email) onSubmit;

  /// What the roster already says about this address — already an admin, or
  /// already invited. Not a permission check (the server makes both calls); it
  /// is so the form can say what will happen rather than report it afterwards.
  final String? note;

  final bool pending;

  @override
  Component build(BuildContext context) {
    final trimmed = value.trim();

    return div(classes: 'z-admins-invite', [
      ZonaiTextField(
        id: 'admin-invite-email',
        fieldLabel: 'Invite by email',
        type: InputType.email,
        value: value,
        placeholder: 'name@example.com',
        autocomplete: 'off',
        disabled: pending,
        onInput: onInput,
      ),
      if (note case final text?) p(classes: 'z-admins-note', [.text(text)]),
      ZonaiButton(
        fullWidth: true,
        disabled: pending || trimmed.isEmpty,
        onClick: () => onSubmit(trimmed),
        child: .text(pending ? 'Sending…' : 'Send invite'),
      ),
    ]);
  }
}

class _AdminRow extends StatelessComponent {
  const _AdminRow({required this.member, required this.refusal, required this.busy, required this.onRemove});

  final AdminMember member;

  /// Why removal is refused, or null when it is allowed. Rendered next to the
  /// disabled control rather than raised on click: neither refusal is an error
  /// (design §4 item 6), and a button that fails when pressed teaches the
  /// person nothing until after they have pressed it.
  final String? refusal;

  final bool busy;
  final void Function() onRemove;

  @override
  Component build(BuildContext context) {
    return div(classes: 'z-admins-row', [
      div(classes: 'z-admins-row-text', [
        span(classes: 'z-admins-row-title', [.text(member.label)]),
        if (refusal case final reason?) span(classes: 'z-admins-note', [.text(reason)]),
      ]),
      ZonaiButton(
        variant: ZonaiButtonVariant.secondary,
        disabled: refusal != null || busy,
        attributes: {if (refusal case final reason?) 'title': reason},
        onClick: onRemove,
        child: .text(busy ? 'Removing…' : 'Remove'),
      ),
    ]);
  }
}

class _InviteRow extends StatelessComponent {
  const _InviteRow({required this.invite, required this.now, required this.busy, required this.onRevoke});

  final PendingInvite invite;
  final DateTime now;
  final bool busy;
  final void Function() onRevoke;

  @override
  Component build(BuildContext context) {
    final expiry = inviteExpiryLabel(invite.expiresAt, now: now);
    final invitedBy = invite.invitedByEmail;

    return div(classes: 'z-admins-row', [
      div(classes: 'z-admins-row-text', [
        span(classes: 'z-admins-row-title', [.text(invite.email)]),
        span(classes: 'z-admins-note', [
          .text(invitedBy == null ? 'Pending — $expiry' : 'Pending — $expiry · invited by $invitedBy'),
        ]),
      ]),
      ZonaiButton(
        variant: ZonaiButtonVariant.secondary,
        disabled: busy,
        onClick: onRevoke,
        child: .text(busy ? 'Revoking…' : 'Revoke'),
      ),
    ]);
  }
}
