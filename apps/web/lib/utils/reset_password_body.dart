import 'package:zonai_schema/payloads.dart'
    show AdminSendResetPasswordAuthBody, ResetPasswordAuthBody, SendResetPasswordAuthBody;

/// Which `POST /auth/reset-password` body a reset should carry.
///
/// A pure function, and separated from the provider for the reason
/// `password_reset_requirement_summary.dart` is: this is a DECISION about a
/// wire payload, and it is testable without a client, a session or a 2000-line
/// stateful component.
///
/// The decision matters because the two bodies are not interchangeable and
/// picking the wrong one FAILS SILENTLY. `AdminSendResetPasswordAuthBody`
/// carries no table -- the server resolves the admin collection from config.
/// Send it for a row in some other password collection and the server looks
/// for an admin account with that address, does not find one, and returns
/// without doing anything: `_sendResetPassword` is deliberately quiet when
/// there is no auth record, so that the endpoint cannot be used to ask whether
/// an address exists. The caller cannot tell that apart from success.
///
/// So: [table] is the row's OWN collection, for a reset sent on someone else's
/// behalf. Omit it only for the dashboard's own door, where the operator is
/// resetting their own admin password and there is no row in hand to name.
ResetPasswordAuthBody resetPasswordBody({required String email, String? table}) {
  if (table == null || table.isEmpty) {
    return AdminSendResetPasswordAuthBody(email: email);
  }
  return SendResetPasswordAuthBody(email: email, table: table);
}
