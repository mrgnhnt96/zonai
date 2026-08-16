import 'package:zonai_schema/payloads.dart';

/// One place a test notification could be sent through.
final class PushTestTarget {
  const PushTestTarget({required this.table, required this.column});

  final String table;

  /// A column whose kind is [ColumnShapeKind.deviceToken].
  final String column;

  /// How the target reads in a picker: `users.deviceToken`.
  String get label => '$table.$column';

  /// Round-trips through a `<select>`, whose value is a single string.
  String get id => label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PushTestTarget && table == other.table && column == other.column;

  @override
  int get hashCode => Object.hash(table, column);

  @override
  String toString() => label;
}

/// Every `deviceToken` column in the loaded schema, in a stable order.
///
/// This is the whole detection story for the test-send panel, and it is
/// deliberately derived rather than configured. `ColumnShapeKind.deviceToken`
/// already exists, is produced by `$.deviceToken(...)` and already reaches the
/// browser in the schema shapes — so "does this project have somewhere to send
/// a notification?" is answerable from data the dashboard has already loaded.
/// A config flag for it would be a second source of truth that could disagree
/// with the schema, and the schema would still be the one that decides whether
/// a send works.
///
/// An empty list means the panel is not rendered at all. Not disabled, not an
/// empty state: a project with no device-token column has no push feature, and
/// a greyed-out control implies a setting somewhere that would switch it on.
///
/// Views are included. A view can surface a `deviceToken` column, and the
/// engine's own check is on the column's *kind*, not on where it lives — so
/// excluding views here would hide targets the server would happily accept.
///
/// Sorted, because the map's iteration order follows however the shapes were
/// loaded. An unsorted picker would reorder itself between renders for no
/// reason a user could see.
List<PushTestTarget> pushTestTargets(Map<String, TableSchemaShape> schemas) {
  final targets = <PushTestTarget>[];

  for (final shape in schemas.values) {
    for (final column in shape.columns) {
      if (column.kind == ColumnShapeKind.deviceToken) {
        targets.add(PushTestTarget(table: shape.table, column: column.name));
      }
    }
  }

  targets.sort((a, b) => a.label.compareTo(b.label));
  return targets;
}

/// The target matching [id], or the first one when nothing matches.
///
/// Falls back rather than returning null: the caller only asks once it knows
/// [targets] is non-empty, and a stale selection — a table renamed under a
/// dashboard left open — should land the operator on a usable target rather
/// than on a form that refuses to send with nothing selected.
PushTestTarget resolvePushTestTarget(List<PushTestTarget> targets, String? id) {
  for (final target in targets) {
    if (target.id == id) return target;
  }
  return targets.first;
}

/// How one finished test send reads to an operator.
///
/// A free function over the payload rather than logic in the component, so the
/// wording — the part that carries the actual diagnosis — is testable without
/// rendering anything.
///
/// The `accepted` wording is careful on purpose. Neither FCM nor APNs offers a
/// delivery receipt, so the honest claim is that the transport took the
/// message, not that a phone showed it. "Delivered" would be the natural word
/// and would be a lie in exactly the case an operator is debugging: a token
/// that is accepted and silently dropped.
String describePushTestResult(PushTestSendResult result) {
  final transport = result.transport.toUpperCase();

  return switch (result.status) {
    PushTestSendStatus.accepted =>
      '$transport accepted the notification for this token. That is not a '
          'delivery receipt — neither transport offers one — so check the '
          'device.',

    // The provider's own words come first and verbatim. `BadDeviceToken` is
    // the case this whole panel is for: the token is valid and was issued by
    // the *other* APNs environment, so the fix is `ApnsConfig.useSandbox`, not
    // the device. Reported as bare "rejected" it sends an operator to look at
    // a phone that is working perfectly.
    PushTestSendStatus.rejected =>
      '$transport permanently rejected this token'
          '${result.detail == null ? '' : ' — ${result.detail}'}. '
          '${_rejectionAdvice(result)}',

    PushTestSendStatus.failed =>
      'Nothing was sent'
          '${result.detail == null ? '.' : ': ${result.detail}'}',
  };
}

String _rejectionAdvice(PushTestSendResult result) {
  final detail = result.detail ?? '';

  if (detail.contains('BadDeviceToken')) {
    return 'A valid token from the other APNs environment answers exactly '
        'this way, so check ApnsConfig.useSandbox against the build that '
        'registered it before assuming the device is gone.';
  }

  return switch (result.reason) {
    PushRejectionReason.unregistered => 'The app was uninstalled, or the registration was rotated.',
    PushRejectionReason.invalidArgument =>
      'The transport read this as malformed. A whole fan-out failing this '
          'way usually means the message, not the tokens.',
    null => 'No reason was recorded.',
  };
}
