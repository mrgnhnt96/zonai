sealed class AuthException implements Exception {
  const AuthException();
}

final class InvalidJwtException extends AuthException {
  const InvalidJwtException();

  @override
  String toString() => 'Invalid JWT';
}

final class JwtRecordNotFoundException extends AuthException {
  const JwtRecordNotFoundException();

  @override
  String toString() => 'JWT record not found';
}

final class UserNotFoundAuthException extends AuthException {
  const UserNotFoundAuthException({required this.table});

  final String table;

  @override
  String toString() => 'User not found for table: $table';
}

final class EmailNotFoundAuthException extends AuthException {
  const EmailNotFoundAuthException({required this.table});

  final String table;

  @override
  String toString() => 'Email not found for table: $table';
}

final class InvalidPasswordOrEmailException extends AuthException {
  const InvalidPasswordOrEmailException();

  @override
  String toString() => 'Invalid password or email';
}

final class AlreadyAuthenticatedException extends AuthException {
  const AlreadyAuthenticatedException();

  @override
  String toString() => 'User already authenticated';
}

final class InvalidOrExpiredCodeException extends AuthException {
  const InvalidOrExpiredCodeException({required this.codeType});

  final String codeType;

  @override
  String toString() => 'Invalid or expired $codeType code';
}

final class CodeExpiredException extends AuthException {
  const CodeExpiredException({required this.codeType});

  final String codeType;

  @override
  String toString() => '$codeType code expired';
}

final class AuthRateLimitException extends AuthException {
  const AuthRateLimitException({required this.waitDuration});

  final Duration waitDuration;

  @override
  String toString() =>
      'Must wait ${waitDuration.inSeconds} seconds before sending a new code';
}

final class InvalidOrExpiredResetPasswordLinkException extends AuthException {
  const InvalidOrExpiredResetPasswordLinkException();

  @override
  String toString() => 'Invalid or expired reset password link';
}

final class ResetPasswordLinkExpiredException extends AuthException {
  const ResetPasswordLinkExpiredException();

  @override
  String toString() => 'Reset password link expired';
}

final class PasswordReuseException extends AuthException {
  const PasswordReuseException();

  @override
  String toString() => 'New password cannot be the same as the old password';
}

final class InvalidOrExpiredVerifyEmailLinkException extends AuthException {
  const InvalidOrExpiredVerifyEmailLinkException();

  @override
  String toString() => 'Invalid or expired verify email link';
}

final class VerifyEmailLinkExpiredException extends AuthException {
  const VerifyEmailLinkExpiredException();

  @override
  String toString() => 'Verify email link expired';
}

final class AuthTableNotFoundException extends AuthException {
  const AuthTableNotFoundException({required this.table});

  final String table;

  @override
  String toString() => 'Cannot authenticate for table: $table';
}

final class AuthEmailForbiddenException extends AuthException {
  const AuthEmailForbiddenException({required this.reason});

  final String reason;

  @override
  String toString() => reason;
}

final class AuthFailedException extends AuthException {
  const AuthFailedException({this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to authenticate: $cause';
    return 'Failed to authenticate';
  }
}

/// Thrown when the registered [ExternalIdpProvisioningGate] rejects
/// provisioning a first-seen external-IdP `sub` for [table].
///
/// HTTP servers typically register a gate that consults rate limits or
/// abuse signals; the default no-op gate (used outside HTTP contexts)
/// never throws.
final class ExternalIdpProvisioningRejectedException extends AuthException {
  const ExternalIdpProvisioningRejectedException({required this.table});

  /// Auth table that provisioning was rejected for.
  final String table;

  @override
  String toString() =>
      'External-IdP first-seen provisioning rejected for table: $table';
}

/// Thrown when a `/auth/oauth/start/:provider` request names a [provider]
/// that isn't in [table]'s `oauthProviders`, or a table that doesn't mix in
/// `OAuth` at all.
final class OAuthProviderNotFoundException extends AuthException {
  const OAuthProviderNotFoundException({
    required this.table,
    required this.provider,
  });

  final String table;
  final String provider;

  @override
  String toString() =>
      'No OAuth provider "$provider" configured for table: $table';
}

/// Thrown when a `redirect_to` supplied to `startOAuth` is neither a
/// relative path nor the app's own [AppConfig.baseUrl] origin — the
/// open-redirect rejection design §4 item 5 requires (see
/// `parts/auth/oauth.dart`'s `_isAllowedOAuthRedirect`).
final class OAuthRedirectNotAllowedException extends AuthException {
  const OAuthRedirectNotAllowedException({required this.redirectTo});

  final String redirectTo;

  @override
  String toString() => 'redirect_to is not allowed: $redirectTo';
}

/// Thrown when an admin invite is accepted by a provider identity whose
/// verified email doesn't match the invite's `target` (design §3.2 step 4).
/// The invite stays unconsumed and no admin row is created -- a different
/// account must not be able to burn someone else's invite.
final class AdminInviteEmailMismatchException extends AuthException {
  const AdminInviteEmailMismatchException();

  @override
  String toString() =>
      "The signed-in account's verified email does not match the invited "
      'address';
}

/// Thrown when removing an admin would leave the `AsAdmin` table with zero
/// rows (design §4 item 6) -- a dashboard that can lock every admin out is a
/// bug, not a feature.
final class LastAdminCannotBeRemovedException extends AuthException {
  const LastAdminCannotBeRemovedException({required this.table});

  final String table;

  @override
  String toString() => 'Cannot remove the last admin account on "$table"';
}

/// Thrown when an admin tries to remove their own account (design §4 item
/// 6) -- self-removal while signed in is indistinguishable from an accident
/// with no recovery path.
final class CannotRemoveSelfAsAdminException extends AuthException {
  const CannotRemoveSelfAsAdminException();

  @override
  String toString() => 'An admin cannot remove their own account';
}
