import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../api/admin_client.dart';
import '../api/api_client.dart';
import '../utils/admin_members.dart';
import '../utils/user_facing_error.dart';
import 'session_user_provider.dart';
import 'toast_provider.dart';

/// Current admins and pending invites, loaded client-side.
///
/// SSR answers [AdminMembers.empty] rather than fetching: `GET /admin/members`
/// needs the caller's bearer token, and the server render has no session of
/// its own to spend. Same shape every other async provider here uses
/// (`dashboardMetricsProvider`, `cronJobsProvider`) — an async provider that
/// notifies after SSR has finished has nothing to repaint.
final adminMembersProvider = AsyncNotifierProvider<AdminMembersNotifier, AdminMembers>(AdminMembersNotifier.new);

class AdminMembersNotifier extends AsyncNotifier<AdminMembers> {
  @override
  Future<AdminMembers> build() async {
    if (!ref.binding.isClient) return AdminMembers.empty;

    return await fetchAdminMembers(server: ref.read(revaliServerProvider));
  }

  Future<void> refresh() async {
    if (!ref.binding.isClient) return;
    ref.invalidateSelf();
  }

  /// Invites [email], then reloads so the new row appears as a pending invite
  /// rather than as whatever the caller assumed the server did.
  ///
  /// Returns true when the invite was sent, so the form can clear itself only
  /// on the path where clearing is right.
  Future<bool> invite(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      ref.read(toastProvider.notifier).showError('Enter an email address to invite.');
      return false;
    }

    try {
      final result = await inviteAdminMember(server: ref.read(revaliServerProvider), email: trimmed);
      final address = result['email'] as String? ?? trimmed;
      final resent = result['isResend'] == true;
      ref.read(toastProvider.notifier).showSuccess(resent ? 'Sent $address a fresh invite link.' : 'Invited $address.');
      ref.invalidateSelf();
      return true;
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
      return false;
    }
  }

  Future<void> revoke(String email) async {
    try {
      await revokeAdminInvite(server: ref.read(revaliServerProvider), email: email);
      ref.read(toastProvider.notifier).showSuccess('Revoked the invite for $email.');
      ref.invalidateSelf();
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    }
  }

  /// Removes an admin. The screen disables this for the two cases design §4
  /// item 6 forbids, so reaching the server's own refusal means the roster
  /// changed under us — which is why the failure is reported and the list
  /// reloaded rather than silently swallowed.
  Future<void> remove(String email) async {
    try {
      await removeAdminMember(server: ref.read(revaliServerProvider), email: email);
      ref.read(toastProvider.notifier).showSuccess('Removed $email and signed out their sessions.');
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    }
    ref.invalidateSelf();
  }
}

/// The signed-in admin's own address, for the "you cannot remove yourself"
/// half of design §4 item 6.
///
/// Null during SSR (the JWT is read from the cookie on the client only), which
/// is why the roster is fetched client-side too: a server render that could
/// not tell who you are would draw the wrong button state and then have to
/// correct itself.
final signedInAdminEmailProvider = Provider<String?>((ref) => ref.watch(sessionUserProvider)?.email);
