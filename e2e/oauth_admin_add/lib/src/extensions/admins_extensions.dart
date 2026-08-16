import 'package:zonai_oauth_admin_add_e2e/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminsExtensions main() => AdminsExtensions();

/// `AsAdmin` never auto-provisions (design §3.3, oauth.dart's isAdmin gate),
/// so `onExternalAuthFirstSeen` never fires for this table -- the default
/// no-op is fine and is not overridden here.
final class AdminsExtensions extends Extension<Admin>
    with AuthExtension<Admin> {
  AdminsExtensions() : super(admins);

  // Same gap `UsersExtensions` (e2e/oauth) documents: the default `onSignIn`
  // sends a `loginNotice` built-in email, which isn't implemented in the
  // runtime's built-in-email dispatch yet -- left in place would fail every
  // admin sign-in this fixture drives.
  @override
  Future<void> onSignIn(Admin user, Jwt? jwt) async {}
}
