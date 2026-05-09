import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

abstract base class Auth<T extends Auth<T>> extends Schema<T> {
  Auth({
    required String email,
    required String password,
    required SchemaBuilder<T> $,
  }) : email = $.text('email', (s) => s.email, email),
       password = $.text('password', (s) => s.password, password);

  final TextColumn email;
  final TextColumn password;
}
