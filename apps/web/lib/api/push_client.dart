import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';

/// Sends one test notification to one device, and reports what came back.
///
/// Synchronous by design: the response describes what the transport said about
/// *this token*. It does not enqueue a push job — a queued send reports totals
/// summed across every job in a drain pass, prunes a rejected token (clearing
/// the column, or deleting the row) and fires the app's `onPushRejected` hook,
/// none of which belong behind a button labelled "send a test".
Future<PushTestSendResult> sendTestPush({
  required Server server,
  required PushTestTargetRef target,
  required String token,
  required String title,
  required String body,
  required DevicePlatform? platform,
}) {
  return server.push.sendTest(
    body: PushTestSendBody(
      table: target.table,
      column: target.column,
      token: token,
      title: title,
      body: body,
      platform: platform,
    ),
  );
}

/// The table/column pair a send is addressed to.
///
/// A minimal record-shaped holder so this file does not depend on the UI's
/// `PushTestTarget`, which carries picker concerns this call has no use for.
typedef PushTestTargetRef = ({String table, String column});
