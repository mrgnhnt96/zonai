// Top-level declarations from a schema file -- the table class and its
// `table('name', ...)` binding, which the templates show without the imports a
// real file has above them.
//
// The row class lives here rather than being imported, because the fragment
// declares the *table* for it: importing the playground's `User` would drag in
// the playground's `UsersId` as well, and the fragment's `UsersId.new` comes
// from the ids file next to it. Two ids libraries, one name, no build.
import 'package:my_app/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.isVerified,
    required this.passwordHash,
    required this.createdAt,
    this.updatedAt,
  });

  final UsersId id;
  final String name;
  final String email;
  final bool isVerified;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

// <<body>>
