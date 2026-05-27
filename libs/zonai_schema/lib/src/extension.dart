import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/schemas/auth_collection.dart';
import 'package:zonai_schema/src/types/email_address.dart';
import 'package:zonai_schema/src/types/jwt.dart';

abstract class Extension<T> {
  Extension(this.schema);

  final Schema schema;

  Table get table => Table.getFor(schema);
  String get collectionName => table.name;

  Future<void> beforeCreate(T object, Jwt? jwt) async {}

  /// Called after a user is created successfully
  ///
  /// By default, sends a [email.send.loginNotice] to the user's email address
  /// if the collection is a [HasEmail] collection
  Future<void> afterCreateSuccess(T row, Jwt? jwt) async {
    if (row case HasEmail(email: final emailColumn)) {
      if (emailColumn.$.valueOf?.call(row) case final String userEmail) {
        email.send.loginNotice(
          EmailAddress(address: userEmail),
          collection: collectionName,
        );
      }
    }
  }

  Future<void> afterCreateError(Object error, Jwt? jwt) async {}

  Future<void> beforeUpdate(T row, Jwt? jwt) async {}
  Future<void> afterUpdateSuccess(T before, T after, Jwt? jwt) async {}
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {}

  Future<void> beforeDelete(T row, Jwt? jwt) async {}
  Future<void> afterDeleteSuccess(T row, Jwt? jwt) async {}
  Future<void> afterDeleteError(Object error, Jwt? jwt) async {}
}

mixin AuthExtension<R> on Extension<R> {
  /// Called when a user signs up
  ///
  /// By default, sends a [email.send.verifyEmail] to the user's email address
  /// if the collection is a [HasEmail] collection
  Future<void> onSignUp(R user, Jwt? jwt) async {
    if (schema case HasEmail(email: final emailColumn)) {
      if (emailColumn.$.valueOf?.call(user) case final String userEmail) {
        email.send.verifyEmail(
          EmailAddress(address: userEmail),
          collection: collectionName,
        );
      }
    }
  }

  /// Called when a user signs in
  ///
  /// By default, sends a [email.send.loginNotice] to the user's email address
  /// if the collection is a [HasEmail] collection
  Future<void> onSignIn(R user, Jwt? jwt) async {
    if (schema case HasEmail(email: final emailColumn)) {
      if (emailColumn.$.valueOf?.call(user) case final String userEmail) {
        email.send.loginNotice(
          EmailAddress(address: userEmail),
          collection: collectionName,
        );
      }
    }
  }

  /// Called when a session token is refreshed via `POST /auth/refresh`.
  ///
  /// The previous access token is revoked when refresh succeeds. Unlike
  /// [onSignIn], no login notice email is sent by default.
  Future<void> onRefresh(R user, Jwt? jwt) async {}

  Future<void> onLogout(R user, Jwt? jwt) async {}
}
