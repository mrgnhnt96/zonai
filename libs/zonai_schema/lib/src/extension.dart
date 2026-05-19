import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/schemas/auth_collection.dart';
import 'package:zonai_schema/src/types/email_address.dart';
import 'package:zonai_schema/src/types/jwt.dart';

abstract class Extension<T> {
  Extension(this.schema);

  final Schema schema;

  Table get table => Table.getFor(schema);
}

mixin CreateExtension<R> on Extension<R> {
  Future<void> beforeCreate(R object, Jwt? jwt) async {}
  Future<void> afterCreateSuccess(R row, Jwt? jwt) async {
    if (row case PasswordAuth() when this is AuthExtension) {
      email.send.loginNotice(EmailAddress(address: row.email));
    }
  }

  Future<void> afterCreateError(Object error, Jwt? jwt) async {}
}

mixin UpdateExtension<R> on Extension<R> {
  Future<void> beforeUpdate(R row, Jwt? jwt) async {}
  Future<void> afterUpdateSuccess(R before, R after, Jwt? jwt) async {}
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {}
}

mixin DeleteExtension<R> on Extension<R> {
  Future<void> beforeDelete(R row, Jwt? jwt) async {}
  Future<void> afterDeleteSuccess(R row, Jwt? jwt) async {}
  Future<void> afterDeleteError(Object error, Jwt? jwt) async {}
}

mixin AuthExtension<R> on Extension<R> {
  Future<void> onSignUp(R user, Jwt? jwt) async {
    if (user case PasswordAuth()) {
      email.send.verifyEmail(EmailAddress(address: user.email));
    }
  }

  Future<void> onSignIn(R user, Jwt? jwt) async {
    if (user case PasswordAuth()) {
      email.send.loginNotice(EmailAddress(address: user.email));
    }
  }

  Future<void> onLogout(R user, Jwt? jwt) async {}
}
