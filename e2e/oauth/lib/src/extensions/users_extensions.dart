import 'package:zonai_oauth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UsersExtensions main() => UsersExtensions();

/// `onExternalAuthFirstSeen` is the *same* hook OAuth first-seen
/// provisioning fires (see `docs/oauth-design.md` §3.3) -- an app that
/// already wired up external-IdP provisioning needs no OAuth-specific
/// extension code at all.
final class UsersExtensions extends Extension<User> with AuthExtension<User> {
  UsersExtensions() : super(users);

  // `AuthExtension.onSignIn`'s default sends a `loginNotice` built-in email
  // for any `HasEmail` table -- unrelated to OAuth, but `.loginNotice` isn't
  // implemented in the runtime's built-in-email dispatch yet, so leaving the
  // default in place would fail every returning sign-in this fixture drives.
  // A real app wiring up OAuth would override this the same way (send its
  // own notice, or nothing) rather than hit that gap.
  @override
  Future<void> onSignIn(User user, Jwt? jwt) async {}

  @override
  Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {
    final sub = claims['sub'] as String;
    final email = claims['email'] as String? ?? '$sub@oauth-e2e.example';
    mutate.create.one(
      tableName: tableName,
      object: <String, dynamic>{
        'id': sub,
        'email': email,
        'is_verified': claims['email_verified'] as bool? ?? false,
        'name': claims['name'] as String? ?? 'OAuth User',
      },
    );
  }
}
