/// Wire format for the dashboard's "send a test notification" panel.
///
/// A test send is deliberately **not** a one-recipient fan-out, and the
/// difference is the whole reason this payload exists rather than reusing the
/// push job types. Three properties of the queue make it the wrong path for a
/// test, each of them by design and none of them a bug:
///
///  * **It cannot say what happened to the recipient.** `drainPushJobs()`
///    returns counts summed across every job in the pass — up to
///    `_maxJobsPerDrain` of them — so a number coming back from a drain is not
///    attributable to the job the operator just enqueued. Worse, `enqueuePush`
///    already kicks an unawaited drain of its own, so a caller that enqueued
///    and then drained races its own kick and is most likely to be handed
///    zeros for a notification that was delivered a moment earlier.
///  * **It prunes.** A permanently rejected token has its column cleared or
///    its whole row deleted, per `PushConfig.onPermanentRejection`. That is
///    correct for a fan-out and unacceptable for a test: pressing "send test"
///    against a stale token would delete a user.
///  * **It fires `onPushRejected`.** The app's production hook would run, for a
///    send the app did not make.
///
/// So a test send goes straight to the same courier the fan-out uses, with the
/// same config and the same classification, and writes nothing. It reuses the
/// transport; it does not reuse the queue.
library;

import 'package:zonai_schema/src/config/apns_config.dart';
import 'package:zonai_schema/src/types/push_outcome.dart';

/// One test notification, and where to send it.
class PushTestSendBody {
  const PushTestSendBody({
    required this.table,
    required this.column,
    required this.token,
    required this.title,
    required this.body,
    this.platform,
  });

  /// The collection holding device tokens.
  ///
  /// Carried even though the send never reads a row from it, because naming it
  /// is what lets the server check [column] really is a `deviceToken` column.
  /// Without that check this endpoint would be "send to any string an admin
  /// pastes", which is the same thing minus the one guard that makes the panel
  /// specific to a project that has push set up at all.
  final String table;

  /// The `deviceToken` column on [table]. Refused if it is any other kind.
  final String column;

  /// The device to send to, pasted by the operator.
  final String token;

  final String title;

  final String body;

  /// Which transport should carry it.
  ///
  /// Null means the same thing it means to a fan-out with no platform column:
  /// FCM. Made explicit here because a test send reads no row, so there is no
  /// platform column to consult — and an iOS token silently sent to FCM
  /// because nobody chose is exactly the confusing failure this panel exists
  /// to clear up.
  final DevicePlatform? platform;

  factory PushTestSendBody.fromJson(Map<String, dynamic> json) {
    return PushTestSendBody(
      table: json['table'] as String,
      column: json['column'] as String,
      token: json['token'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      platform: DevicePlatform.tryParse(json['platform'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table,
    'column': column,
    'token': token,
    'title': title,
    'body': body,
    'platform': ?platform?.toJson(),
  };
}

/// What became of the one recipient.
enum PushTestSendStatus {
  /// The transport accepted the message for this token.
  ///
  /// Not a delivery receipt. Neither FCM nor APNs offers one, and the panel
  /// says so rather than letting "delivered" be read as "it arrived".
  accepted,

  /// The transport will never accept this token again.
  rejected,

  /// Nothing was sent, or the attempt failed for a reason that is not about
  /// this token: no push config, no transport for the platform, bad
  /// credentials, a timeout.
  failed;

  String toJson() => name;

  static PushTestSendStatus fromJson(String value) =>
      PushTestSendStatus.values.byName(value);
}

/// The result of one test send, as the operator needs to read it.
class PushTestSendResult {
  const PushTestSendResult({
    required this.status,
    required this.token,
    required this.transport,
    this.reason,
    this.detail,
  });

  final PushTestSendStatus status;

  /// Echoed back so a result cannot be read against the wrong token after the
  /// operator has edited the field.
  final String token;

  /// Which transport actually carried it — `apns`, `fcm`, or `none` when
  /// nothing could.
  ///
  /// Load-bearing for diagnosis, not decoration. `BadDeviceToken` only means
  /// "wrong environment" if the answer came from APNs, and an iOS token that
  /// went out over FCM because no APNs config exists fails for a different
  /// reason entirely. Without this the operator cannot tell those apart.
  final String transport;

  /// Set when [status] is [PushTestSendStatus.rejected].
  final PushRejectionReason? reason;

  /// The provider's own words, verbatim — `400 BadDeviceToken`,
  /// `404 UNREGISTERED`, a transport error message.
  ///
  /// The field the panel is really for. A test notification that reports
  /// "failed" and nothing else tells an operator less than no panel at all,
  /// because it looks like an answer.
  final String? detail;

  /// Reads [outcome] into the shape the panel renders.
  factory PushTestSendResult.fromOutcome(
    PushOutcome outcome, {
    required String transport,
  }) {
    return switch (outcome) {
      PushDelivered() => PushTestSendResult(
        status: PushTestSendStatus.accepted,
        token: outcome.token,
        transport: transport,
      ),
      PushPermanentlyRejected(:final reason, :final detail) =>
        PushTestSendResult(
          status: PushTestSendStatus.rejected,
          token: outcome.token,
          transport: transport,
          reason: reason,
          detail: detail,
        ),
      PushTransientlyFailed(:final detail) => PushTestSendResult(
        status: PushTestSendStatus.failed,
        token: outcome.token,
        transport: transport,
        detail: detail,
      ),
    };
  }

  factory PushTestSendResult.fromJson(Map<String, dynamic> json) {
    return PushTestSendResult(
      status: PushTestSendStatus.fromJson(json['status'] as String),
      token: json['token'] as String,
      transport: json['transport'] as String,
      reason: switch (json['reason']) {
        final String value => PushRejectionReason.fromJson(value),
        _ => null,
      },
      detail: json['detail'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.toJson(),
    'token': token,
    'transport': transport,
    'reason': ?reason?.toJson(),
    'detail': ?detail,
  };
}
