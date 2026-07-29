import 'package:zonai_signup_backfill_repro/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UsersExtensions main() => UsersExtensions();

/// Backfills the matching pending invite's `user_id` when a user signs up,
/// the same shape of hook the "onSignUp never persists its writes" report
/// was written against.
final class UsersExtensions extends Extension<User> with AuthExtension<User> {
  UsersExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    final invite = await get.one(
      tableName: 'invites',
      where: Eq('email', user.email),
    );

    if (invite == null) return;

    mutate.update.one(
      table: 'invites',
      updates: [Update.column('user_id', .literal(user.id.value))],
      where: Eq('id', invite['id'] as String),
    );
  }
}
