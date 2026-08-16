import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/payloads/push_test_send.dart';
import 'package:zonai_schema/src/types/push_message.dart';

/// The dashboard's test-send verb.
///
/// Push has had no HTTP surface at all until now, and this adds exactly one
/// route rather than exposing the fan-out. That is the deliberate part: a
/// general "enqueue a push" endpoint would put a fan-out over an arbitrary
/// `where` one admin token away from every device in a project, and nothing
/// about a test panel needs it.
///
/// The gate is the same shape as `DashboardHandler.metrics` — parse the bearer
/// token, refuse anything that is not an admin, refuse before doing any work —
/// and it is the outer of two: `ZonaiDb.sendTestPush` checks admin again
/// host-side, because its request arrives over IPC from a worker process and
/// the caller's word is not the check.
class PushHandler {
  const PushHandler();

  Future<PushTestSendResult> sendTest(
    String? authorization, {
    required PushTestSendBody body,
  }) async {
    final jwt = await zonaiDB.parseJwt(
      _parseBearerAuthorization(authorization),
    );
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw const TableAccessDeniedException(
        table: '_push',
        operation: 'send_test',
      );
    }

    return zonaiDB.sendTestPush(
      // No `collapseKey`. A fan-out sets one so a crash-resumed duplicate is
      // invisible on the device; a test send is at-most-once and an operator
      // pressing the button twice wants to see two notifications, not one
      // replacing the other and looking like the second never arrived.
      message: PushMessage(title: body.title, body: body.body),
      table: body.table,
      column: body.column,
      token: body.token.trim(),
      platform: body.platform,
      jwt: jwt,
    );
  }

  String? _parseBearerAuthorization(String? authorizationHeader) {
    if (authorizationHeader == null) {
      return null;
    }

    final trimmed = authorizationHeader.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      return trimmed.substring(prefix.length).trim();
    }

    return null;
  }
}
