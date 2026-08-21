import 'package:zonai_schema/payloads.dart';

/// The most rows one send from the dashboard will address.
///
/// The endpoint behind this panel sends to exactly one token per request, and
/// that is deliberate on the server's side — a general "enqueue a fan-out"
/// route would put every device in a project one admin token away. So a
/// selection of N rows is N requests from the browser, and the cap is what
/// stops an operator who pressed "All 12,480" from starting twelve thousand of
/// them.
///
/// It is a refusal rather than a truncation. Sending to the first 50 of a
/// larger selection would look like it worked and quietly miss everyone else;
/// a real fan-out belongs in `push()` on the server, where it is a job with a
/// cursor, retries and an `onPushRejected` hook.
const pushRowSelectionLimit = 50;

/// A device-token column on the table being browsed.
///
/// [tokenIndex] is resolved against the *projection* the rows came back in,
/// not against the schema's column order, because that is what indexes a row.
/// A column the projection does not carry produces no target at all rather
/// than a target that would read the wrong cell.
final class PushRowTarget {
  const PushRowTarget({
    required this.table,
    required this.column,
    required this.tokenIndex,
    this.platformColumn,
    this.platformIndex,
  });

  final String table;

  /// A column whose kind is [ColumnShapeKind.deviceToken].
  final String column;

  /// Where the token sits in a row of the current projection.
  final int tokenIndex;

  /// A column whose values say which transport a row's device wants, when the
  /// table has one. Null means every row is sent the same way.
  final String? platformColumn;

  final int? platformIndex;

  /// How the target reads in a picker: `users.deviceToken`.
  String get label => '$table.$column';

  /// Round-trips through a `<select>`, whose value is a single string.
  String get id => label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushRowTarget &&
          table == other.table &&
          column == other.column &&
          tokenIndex == other.tokenIndex &&
          platformColumn == other.platformColumn &&
          platformIndex == other.platformIndex;

  @override
  int get hashCode => Object.hash(table, column, tokenIndex, platformColumn, platformIndex);

  @override
  String toString() => label;
}

/// Every `deviceToken` column of the table being browsed, in a stable order.
///
/// This is the whole detection story for the send action, and it is
/// deliberately derived rather than configured. `ColumnShapeKind.deviceToken`
/// already exists, is produced by `$.deviceToken(...)` and already reaches the
/// browser in the schema shapes — so "can this table's rows be sent to?" is
/// answerable from data the dashboard has already loaded. A config flag for it
/// would be a second source of truth that could disagree with the schema, and
/// the schema would still be the one that decides whether a send works.
///
/// An empty list means the action is not offered at all. Not disabled: a table
/// with no device-token column has no device to reach, and a greyed-out button
/// implies a setting somewhere that would switch it on.
///
/// Sorted by column name, because a picker that reordered itself between
/// renders would move under the operator's cursor for no reason they can see.
List<PushRowTarget> pushRowTargets({
  required String table,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
}) {
  final platform = _platformColumn(columns, columnShapes);

  final targets = <PushRowTarget>[];
  for (final shape in columnShapes) {
    if (shape.kind != ColumnShapeKind.deviceToken) continue;
    final index = columns.indexOf(shape.name);
    if (index < 0) continue;
    targets.add(
      PushRowTarget(
        table: table,
        column: shape.name,
        tokenIndex: index,
        platformColumn: platform?.name,
        platformIndex: platform?.index,
      ),
    );
  }

  targets.sort((a, b) => a.column.compareTo(b.column));
  return targets;
}

/// The target matching [id], or the first one when nothing matches.
///
/// Falls back rather than returning null: the caller only asks once it knows
/// [targets] is non-empty, and a stale selection — a table refreshed under an
/// open dialog — should land the operator on a usable target rather than on a
/// form that refuses to send with nothing selected.
PushRowTarget resolvePushRowTarget(List<PushRowTarget> targets, String? id) {
  for (final target in targets) {
    if (target.id == id) return target;
  }
  return targets.first;
}

/// Column names that mean "which transport this row's device wants".
///
/// Matched case-insensitively, with `_` stripped, so `platform`,
/// `device_platform` and `devicePlatform` are all the same name.
const _platformColumnNames = {'platform', 'deviceplatform', 'osplatform', 'os'};

/// The column a row's transport can be read from, if the table has one.
///
/// Nothing in the schema *declares* a platform column — `push()` takes it as
/// an argument at the call site — so this has to recognise one, and there are
/// exactly two shapes worth recognising:
///
/// * an enum whose entire domain parses as a [DevicePlatform]. Nothing else
///   can be: a column that can only ever hold `ios` or `android` is a platform
///   column whatever it is named.
/// * a text column named for the job. This is the shape `docs/push.md` itself
///   recommends (`platform = $.text('platform', ...)`), so refusing it would
///   mean the dashboard could not route the schema the documentation tells
///   people to write.
///
/// A status enum that merely *contains* `ios` does not qualify, and neither
/// does a text column named something else — both would be the dashboard
/// guessing which transport a real user's notification goes through.
///
/// Nothing here is silent: the dialog names the column it reads, and the
/// operator can override the whole send. When no column qualifies, every row
/// is sent the same way and the operator picks which way.
({String name, int index})? _platformColumn(List<String> columns, List<ColumnShape> columnShapes) {
  for (final shape in columnShapes) {
    if (!_isPlatformColumn(shape)) continue;
    final index = columns.indexOf(shape.name);
    if (index < 0) continue;
    return (name: shape.name, index: index);
  }
  return null;
}

bool _isPlatformColumn(ColumnShape shape) {
  if (shape.kind == ColumnShapeKind.enum_) {
    if (shape.enumValues.isEmpty) return false;
    return shape.enumValues.every((value) => DevicePlatform.tryParse(value) != null);
  }

  if (shape.kind != ColumnShapeKind.text) return false;
  return _platformColumnNames.contains(shape.name.toLowerCase().replaceAll('_', ''));
}

/// One selected row's device, ready to send to.
final class PushRecipient {
  const PushRecipient({required this.token, required this.label, this.platform});

  final String token;

  /// How this row is named back to the operator — `id=42`, not the token.
  /// A result list keyed on the token alone is unreadable, and the token is
  /// the one field an operator cannot check at a glance.
  final String label;

  /// Read from the table's platform column when it has one, and null when it
  /// does not — null being FCM, which is what a fan-out without a platform
  /// column does.
  final DevicePlatform? platform;
}

/// What a selection turned into: who can be reached, and who was dropped.
typedef PushRecipientScan = ({List<PushRecipient> recipients, int withoutToken, int duplicates});

/// Turns selected rows into recipients, and counts what fell out.
///
/// Two things are dropped, and both are reported rather than silently handled,
/// because "Send to 2" under a selection of 3 is the only place an operator
/// finds out that a row they picked is not going anywhere:
///
/// * a row whose token cell is null or blank — a user who has not registered a
///   device, which is the ordinary case in any table that has ever had one;
/// * a token that already appeared in an earlier row — two rows sharing a
///   device would otherwise put two identical notifications on one phone, and
///   the second would look like a duplicate bug rather than a duplicate row.
PushRecipientScan scanPushRecipients({
  required PushRowTarget target,
  required List<List<Object?>> rows,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
}) {
  final recipients = <PushRecipient>[];
  final seen = <String>{};
  var withoutToken = 0;
  var duplicates = 0;

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final raw = row.elementAtOrNull(target.tokenIndex);
    final token = raw is String ? raw.trim() : '';
    if (token.isEmpty) {
      withoutToken++;
      continue;
    }
    if (!seen.add(token)) {
      duplicates++;
      continue;
    }

    final platformIndex = target.platformIndex;
    final platformValue = platformIndex == null ? null : row.elementAtOrNull(platformIndex);

    recipients.add(
      PushRecipient(
        token: token,
        label: pushRowLabel(row: row, index: i, columns: columns, columnShapes: columnShapes),
        platform: DevicePlatform.tryParse(platformValue is String ? platformValue : null),
      ),
    );
  }

  return (recipients: recipients, withoutToken: withoutToken, duplicates: duplicates);
}

/// How one row is named in the dialog: `id=42`, or `email=sam@example.com`.
///
/// Primary keys, because that is what the operator sees in the table and what
/// they would search for afterwards. A table without one falls back to its
/// position in the selection — wrong to *identify* a row by, but it is only
/// ever read next to the row's own result line.
String pushRowLabel({
  required List<Object?> row,
  required int index,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
}) {
  final parts = <String>[];
  for (final shape in columnShapes) {
    if (!shape.isPrimaryKey) continue;
    final at = columns.indexOf(shape.name);
    if (at < 0) continue;
    parts.add('${shape.name}=${row.elementAtOrNull(at)}');
  }

  if (parts.isEmpty) return 'Row ${index + 1}';
  return parts.join(' · ');
}

/// How one finished send reads to an operator.
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
String describePushSendResult(PushTestSendResult result) {
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

    // The prefix is dropped when the transport's own words already open with
    // it. `AppConfig.push is not configured` comes back as a sentence that
    // ends "Nothing was sent." — prefixed again it reads as a stutter, and a
    // line an operator has to read twice is a line they stop reading.
    PushTestSendStatus.failed => switch (result.detail) {
      null => 'Nothing was sent.',
      final detail when detail.contains('Nothing was sent') => detail,
      final detail => 'Nothing was sent: $detail',
    },
  };
}

/// The one-line tally over a whole send: `2 accepted · 1 rejected`.
///
/// Counts, not a verdict. A send where four tokens were accepted and one was
/// rejected is neither a success nor a failure, and a single word for it would
/// have to pick one — which is how the rejected token stops being looked at.
/// [failed] here counts requests that never produced an outcome as well as
/// outcomes whose status is `failed`; both mean nothing reached a device, and
/// the per-row lines below the summary say which is which.
String describePushSendSummary({required int accepted, required int rejected, required int failed}) {
  final parts = <String>[
    if (accepted > 0) '$accepted accepted',
    if (rejected > 0) '$rejected rejected',
    if (failed > 0) '$failed failed',
  ];

  if (parts.isEmpty) return 'Nothing was sent.';
  return parts.join(' · ');
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
