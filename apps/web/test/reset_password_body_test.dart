import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart' show AdminSendResetPasswordAuthBody, SendResetPasswordAuthBody;
import 'package:zonai_web/utils/reset_password_body.dart';

/// Which body a "Reset password" carries — a decision, tested where it is one.
///
/// This existed as a bug for as long as the row action did. The data browser's
/// "Reset password" is gated on `sessionCanEdit` and ANY password collection,
/// so it appears on `users` rows; it sent the admin-shaped body regardless,
/// which resolves the ADMIN table server-side. On a `users` row the server
/// looked for an admin with that address, found none, and returned without
/// doing anything — `_sendResetPassword` is deliberately silent when there is
/// no auth record, so the endpoint cannot be used to ask whether an address
/// exists. The operator got a success toast and the account heard nothing.
///
/// That failure mode is why these assertions are worth their length: the wrong
/// choice here produces no error anywhere, so the only thing that can catch it
/// is an assertion on the body itself.
void main() {
  group('a reset sent on another row-s behalf', () {
    test('names the row own collection', () {
      final body = resetPasswordBody(email: 'someone@example.com', table: 'users');

      expect(body, isA<SendResetPasswordAuthBody>());
      expect((body as SendResetPasswordAuthBody).table, 'users');
      expect(body.email, 'someone@example.com');
    });

    test('it carries the table on the wire, not just in Dart', () {
      // The panel sends the row's `sqliteName`. A body that dropped it in
      // `toJson` would be the same silent no-op with a different cause.
      final json = resetPasswordBody(email: 'someone@example.com', table: 'members').toJson();

      expect(json['type'], 'sendResetPassword');
      expect(json['table'], 'members');
      expect(json['email'], 'someone@example.com');
    });

    test('a non-admin collection is NOT turned into an admin reset', () {
      // The regression, stated as itself: this is the exact call the row
      // action makes, and before the fix it produced the admin body.
      expect(
        resetPasswordBody(email: 'user@example.com', table: 'users'),
        isNot(isA<AdminSendResetPasswordAuthBody>()),
      );
    });
  });

  group('the dashboard own door', () {
    test('omitting the table asks for an admin reset', () {
      // `reset_password_request_screen` — the operator resetting their OWN
      // admin password. There is no row in hand to name, and the admin table
      // is resolved server-side from config, so the admin body is correct
      // here and must stay reachable.
      final body = resetPasswordBody(email: 'admin@example.com');

      expect(body, isA<AdminSendResetPasswordAuthBody>());
      expect(body.email, 'admin@example.com');
      expect(body.toJson()['table'], isNull);
    });

    test('an empty table is treated as absent, not as a collection named ""', () {
      // A defensive equivalence rather than a shape the panel produces:
      // `sqliteName` is never empty. Sending `table: ''` would ask the server
      // to resolve a collection with no name, which is a worse failure than
      // the admin default.
      expect(resetPasswordBody(email: 'admin@example.com', table: ''), isA<AdminSendResetPasswordAuthBody>());
    });
  });
}
