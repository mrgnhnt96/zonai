import 'package:zonai_external_auth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UsersExtensions main() => UsersExtensions();

final class UsersExtensions extends Extension<User> with AuthExtension<User> {
  UsersExtensions() : super(users);

  @override
  Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {
    final sub = claims['sub'] as String;
    final email = claims['email'] as String? ?? '$sub@external.example';
    mutate.create.one(
      tableName: tableName,
      object: <String, dynamic>{
        'id': sub,
        'email': email,
        'name': claims['user_metadata'] is Map
            ? (claims['user_metadata'] as Map)['full_name'] as String? ??
                  'External User'
            : 'External User',
      },
    );
  }
}
