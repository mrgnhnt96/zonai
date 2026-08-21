import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../api/push_client.dart' as api;
import '../utils/push_row_targets.dart';
import '../utils/user_facing_error.dart';

/// The row-selection send dialog: who it is addressed to, and what came back.
final pushSendProvider = NotifierProvider<PushSendNotifier, PushSendState>(PushSendNotifier.new);

/// Which transport a send is routed through.
///
/// `fromColumn` is only offered when the table has a platform column, and is
/// the default when it does — a per-row answer beats one the operator has to
/// give for a mixed selection. The rest mirror the fan-out's own behaviour:
/// no platform means FCM.
enum PushPlatformChoice { fromColumn, defaultFcm, ios, android }

/// What one recipient's send ended as.
///
/// [result] is kept whole rather than reduced to a sentence at the moment of
/// arrival, so a rejection can be styled differently from an acceptance and
/// still render the transport's own words. [error] is the separate case where
/// the request itself failed — a refused gate, a dead server — and never
/// carries a per-device meaning.
final class PushSendOutcome {
  const PushSendOutcome({required this.recipient, this.result, this.error});

  final PushRecipient recipient;
  final PushTestSendResult? result;
  final String? error;

  bool get isAccepted => result?.status == PushTestSendStatus.accepted;
  bool get isRejected => result?.status == PushTestSendStatus.rejected;
  bool get isFailed => error != null || result?.status == PushTestSendStatus.failed;

  /// The tone class the dialog styles this line with.
  String get tone => switch (this) {
    _ when isAccepted => 'accepted',
    _ when isRejected => 'rejected',
    _ => 'failed',
  };

  String get description => error ?? describePushSendResult(result!);
}

/// The dialog's whole state, including the rows it was opened over.
///
/// The rows are held rather than the recipients they resolve to, because
/// switching token column has to re-read them: a table with two device-token
/// columns addresses different devices depending on which one is picked, and
/// recomputing from the rows is the only way that stays true.
final class PushSendState {
  const PushSendState({
    this.isOpen = false,
    this.table = '',
    this.columns = const [],
    this.columnShapes = const [],
    this.rows = const [],
    this.targets = const [],
    this.targetId,
    this.title = 'Test notification',
    this.body = 'Sent from the Zonai dashboard.',
    this.platform = PushPlatformChoice.defaultFcm,
    this.isSending = false,
    this.outcomes = const [],
    this.error,
  });

  final bool isOpen;
  final String table;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final List<List<Object?>> rows;
  final List<PushRowTarget> targets;

  /// [PushRowTarget.id] of the selected token column, or null for "the first".
  final String? targetId;

  final String title;
  final String body;
  final PushPlatformChoice platform;
  final bool isSending;

  /// Filled in recipient order as the send progresses, so the dialog can show
  /// how far it has got rather than a spinner over an unknown number of
  /// requests.
  final List<PushSendOutcome> outcomes;

  /// A failure that belongs to the dialog rather than to any one recipient.
  final String? error;

  PushRowTarget? get target => targets.isEmpty ? null : resolvePushRowTarget(targets, targetId);

  PushRecipientScan get scan {
    final target = this.target;
    if (target == null) return (recipients: const [], withoutToken: rows.length, duplicates: 0);
    return scanPushRecipients(target: target, rows: rows, columns: columns, columnShapes: columnShapes);
  }

  List<PushRecipient> get recipients => scan.recipients;

  bool get canSend => !isSending && recipients.isNotEmpty && title.trim().isNotEmpty;

  /// Whether the table has somewhere to read each row's transport from.
  bool get hasPlatformColumn => target?.platformColumn != null;

  int get accepted => outcomes.where((o) => o.isAccepted).length;
  int get rejected => outcomes.where((o) => o.isRejected).length;
  int get failed => outcomes.where((o) => o.isFailed).length;

  PushSendState copyWith({
    bool? isOpen,
    String? table,
    List<String>? columns,
    List<ColumnShape>? columnShapes,
    List<List<Object?>>? rows,
    List<PushRowTarget>? targets,
    String? targetId,
    String? title,
    String? body,
    PushPlatformChoice? platform,
    bool? isSending,
    List<PushSendOutcome>? outcomes,
    String? error,
    bool clearOutcome = false,
  }) {
    return PushSendState(
      isOpen: isOpen ?? this.isOpen,
      table: table ?? this.table,
      columns: columns ?? this.columns,
      columnShapes: columnShapes ?? this.columnShapes,
      rows: rows ?? this.rows,
      targets: targets ?? this.targets,
      targetId: targetId ?? this.targetId,
      title: title ?? this.title,
      body: body ?? this.body,
      platform: platform ?? this.platform,
      isSending: isSending ?? this.isSending,
      outcomes: clearOutcome ? const [] : (outcomes ?? this.outcomes),
      error: clearOutcome ? null : (error ?? this.error),
    );
  }
}

class PushSendNotifier extends Notifier<PushSendState> {
  @override
  PushSendState build() => const PushSendState();

  /// Opens the dialog over an already-resolved set of rows.
  ///
  /// The rows arrive from the caller rather than being fetched here: the
  /// selection may cover pages that are not loaded, and `rowsForSelection` is
  /// where that already lives. This keeps the dialog free of a second idea of
  /// what "selected" means.
  void open({
    required String table,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
    required List<List<Object?>> rows,
    required List<PushRowTarget> targets,
  }) {
    final hasPlatformColumn = targets.isNotEmpty && targets.first.platformColumn != null;

    state = PushSendState(
      isOpen: true,
      table: table,
      columns: columns,
      columnShapes: columnShapes,
      rows: rows,
      targets: targets,
      // Per-row routing whenever the table can answer it, because a mixed
      // selection has no single right answer for the operator to give.
      platform: hasPlatformColumn ? PushPlatformChoice.fromColumn : PushPlatformChoice.defaultFcm,
      // Title and body deliberately reset to the defaults on every open. The
      // alternative — remembering the last message — is how a note written for
      // one user goes to a different one.
    );
  }

  /// Closes the dialog, unless a send is still in flight.
  ///
  /// Refusing to close mid-send is not politeness: the outcomes are the only
  /// record of what happened, they are not written anywhere else, and half of
  /// the notifications have already left. A dialog that vanished at that
  /// moment would take the rejections with it.
  void close() {
    if (state.isSending) return;
    state = const PushSendState();
  }

  void selectTarget(String id) => state = state.copyWith(targetId: id, clearOutcome: true);

  void setTitle(String value) => state = state.copyWith(title: value);

  void setBody(String value) => state = state.copyWith(body: value);

  void setPlatform(PushPlatformChoice value) => state = state.copyWith(platform: value, clearOutcome: true);

  /// Sends to every recipient, four at a time, reporting as it goes.
  ///
  /// Four rather than all at once: the browser would open one connection per
  /// recipient, and fifty simultaneous sends is a self-inflicted burst against
  /// both the server's admin gate and the transport. Four rather than one at a
  /// time because a serial pass over fifty tokens, each a round trip to APNs,
  /// is a minute of an operator watching a spinner.
  ///
  /// Nothing is aborted on a failure. Each recipient's answer is about that
  /// device — a rejected token says nothing about the next one — and stopping
  /// early would leave the operator unable to tell "not sent" from "sent and
  /// rejected" for everyone after it.
  Future<void> send() async {
    if (!state.canSend) return;

    final target = state.target;
    if (target == null) return;

    final recipients = state.recipients;
    final title = state.title.trim();
    final body = state.body.trim();
    final choice = state.platform;
    final server = ref.read(revaliServerProvider);

    // The previous outcomes are cleared before the request rather than
    // overwritten after it. Leaving a green "accepted" on screen while the
    // next send is in flight invites reading it as the new answer.
    state = state.copyWith(isSending: true, clearOutcome: true);

    const batchSize = 4;
    final done = <PushSendOutcome>[];

    for (var i = 0; i < recipients.length; i += batchSize) {
      final batch = recipients.sublist(i, (i + batchSize).clamp(0, recipients.length));
      final settled = await Future.wait([
        for (final recipient in batch)
          _sendOne(server: server, target: target, recipient: recipient, title: title, body: body, choice: choice),
      ]);

      done.addAll(settled);

      // The dialog may have been closed by a reload or a route change while
      // this was in flight; `state` on a disposed notifier throws.
      if (!ref.mounted) return;
      state = state.copyWith(outcomes: List.unmodifiable(done));
    }

    if (!ref.mounted) return;
    state = state.copyWith(isSending: false);
  }

  Future<PushSendOutcome> _sendOne({
    required Server server,
    required PushRowTarget target,
    required PushRecipient recipient,
    required String title,
    required String body,
    required PushPlatformChoice choice,
  }) async {
    try {
      final result = await api.sendTestPush(
        server: server,
        target: (table: target.table, column: target.column),
        token: recipient.token,
        title: title,
        body: body,
        platform: resolvePushPlatform(choice: choice, rowPlatform: recipient.platform),
      );
      return PushSendOutcome(recipient: recipient, result: result);
    } catch (error) {
      return PushSendOutcome(recipient: recipient, error: userFacingError(error));
    }
  }
}

/// What the transport argument is for one recipient.
///
/// Null is FCM, matching a fan-out with no platform column — including the
/// `fromColumn` case where the row's own value did not parse. An unrecognised
/// string in one row is that row's problem, and the fan-out already answers it
/// the same way rather than failing the send.
DevicePlatform? resolvePushPlatform({required PushPlatformChoice choice, required DevicePlatform? rowPlatform}) {
  return switch (choice) {
    PushPlatformChoice.fromColumn => rowPlatform,
    PushPlatformChoice.defaultFcm => null,
    PushPlatformChoice.ios => DevicePlatform.ios,
    PushPlatformChoice.android => DevicePlatform.android,
  };
}
