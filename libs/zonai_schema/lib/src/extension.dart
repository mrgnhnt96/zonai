import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/schemas/auth_table.dart';
import 'package:zonai_schema/src/types/email_address.dart';
import 'package:zonai_schema/src/types/jwt.dart';

abstract class Extension<T> {
  Extension(this.schema);

  final rd.Schema schema;

  rd.TableMeta get table => schema.$;
  String get tableName => table.name;

  Future<void> beforeCreate(T object, Jwt? jwt) async {}

  /// Called after a user is created successfully
  ///
  /// By default, sends a [email.send.loginNotice] to the user's email address
  /// if the table is a [HasEmail] collection
  Future<void> afterCreateSuccess(T row, Jwt? jwt) async {
    if (row case HasEmail(email: final emailColumn)) {
      if (emailColumn.readValueOf(row) case final String userEmail) {
        email.send.loginNotice(
          EmailAddress(address: userEmail),
          table: tableName,
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
  /// if the table is a [HasEmail] collection
  Future<void> onSignUp(R user, Jwt? jwt) async {
    if (schema case HasEmail(email: final emailColumn)) {
      if (emailColumn.readValueOf(user) case final String userEmail) {
        email.send.verifyEmail(
          EmailAddress(address: userEmail),
          table: tableName,
        );
      }
    }
  }

  /// Called when a user signs in
  ///
  /// By default, sends a [email.send.loginNotice] to the user's email address
  /// if the table is a [HasEmail] collection
  Future<void> onSignIn(R user, Jwt? jwt) async {
    if (schema case HasEmail(email: final emailColumn)) {
      if (emailColumn.readValueOf(user) case final String userEmail) {
        email.send.loginNotice(
          EmailAddress(address: userEmail),
          table: tableName,
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

  /// Called after a password reset email is sent to the user.
  ///
  /// Unlike [onSignIn], no email is sent by default — the server sends the
  /// reset link before this hook runs.
  Future<void> onPasswordReset(R user, Jwt? jwt) async {}

  /// Called when an external IdP token's `sub` does not match any
  /// existing row in this auth collection. Use this hook to insert
  /// the missing row from the verified [claims], so the auth flow
  /// can resolve `Jwt.user` and proceed.
  ///
  /// Use the `mutate.create.one(...)` global from inside this hook
  /// to insert the row. Mutations queued during this hook are
  /// flushed inline (not after the request transaction) so the auth
  /// pipeline can re-fetch the new row immediately. The hook runs
  /// under a `ProvisioningJwt` scoped to this collection — it can
  /// only mutate this auth table.
  ///
  /// If the hook returns without provisioning (the default no-op,
  /// or a hook that decides [claims] doesn't satisfy required
  /// invariants), the auth request fails with the same
  /// `UserNotFoundAuthException` callers see without the hook.
  Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {}
}
