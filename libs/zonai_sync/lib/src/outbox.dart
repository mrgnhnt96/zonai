import 'package:meta/meta.dart';

enum OutboxOp { upsert, delete }

enum OutboxState {
  pending,

  /// Failed permanently (403/400/422, or retries exhausted). Kept, visible to
  /// the UI, and never retried until the app calls retryDeadLetter.
  dead,
}

/// One unpushed local change. There is at most one per (table, rowId):
/// later writes coalesce into it (see [Outbox.coalesce]).
@immutable
final class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.table,
    required this.rowId,
    required this.op,
    required this.payload,
    required this.changedFields,
    required this.baseRev,
    required this.version,
    this.attempts = 0,
    this.state = OutboxState.pending,
    this.lastError,
    this.notBefore,
    this.sent = false,
  });

  factory OutboxEntry.fromJson(Map<String, Object?> json) => OutboxEntry(
    id: json['id']! as int,
    table: json['table']! as String,
    rowId: json['rowId']! as String,
    op: OutboxOp.values.byName(json['op']! as String),
    payload: (json['payload']! as Map).cast<String, Object?>(),
    changedFields: (json['changedFields']! as List).cast<String>().toSet(),
    baseRev: json['baseRev'] as int?,
    version: json['version']! as int,
    attempts: json['attempts']! as int,
    state: OutboxState.values.byName(json['state']! as String),
    lastError: json['lastError'] as String?,
    notBefore: json['notBefore'] as int?,
    sent: json['sent'] as bool? ?? false,
  );

  /// Monotonic per store; push order within a table.
  final int id;
  final String table;
  final String rowId;
  final OutboxOp op;

  /// The full row as the client last wrote it (wire format).
  final Map<String, Object?> payload;

  /// Fields changed locally since [baseRev] — what a field-merge re-applies.
  final Set<String> changedFields;

  /// The server revision this change was made against; null when the row has
  /// never been on the server (a create).
  final int? baseRev;

  /// Bumped on every coalesce, so a push that raced a new local write knows
  /// not to delete the newer entry.
  final int version;
  final int attempts;
  final OutboxState state;
  final String? lastError;

  /// Epoch ms before which this entry must not be retried (backoff).
  final int? notBefore;

  /// Whether a create for this row has ever been SENT. Once it has, the
  /// server may hold the row even if no response came back (a timeout, a
  /// dropped connection), so a later delete must reach the server as a
  /// tombstone instead of cancelling locally.
  final bool sent;

  bool get isCreate => baseRev == null;

  OutboxEntry copyWith({
    OutboxOp? op,
    Map<String, Object?>? payload,
    Set<String>? changedFields,
    int? baseRev,
    bool clearBaseRev = false,
    int? version,
    int? attempts,
    OutboxState? state,
    String? lastError,
    int? notBefore,
    bool clearNotBefore = false,
    bool? sent,
  }) => OutboxEntry(
    id: id,
    table: table,
    rowId: rowId,
    op: op ?? this.op,
    payload: payload ?? this.payload,
    changedFields: changedFields ?? this.changedFields,
    baseRev: clearBaseRev ? null : baseRev ?? this.baseRev,
    version: version ?? this.version,
    attempts: attempts ?? this.attempts,
    state: state ?? this.state,
    lastError: lastError ?? this.lastError,
    notBefore: clearNotBefore ? null : notBefore ?? this.notBefore,
    sent: sent ?? this.sent,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'table': table,
    'rowId': rowId,
    'op': op.name,
    'payload': payload,
    'changedFields': changedFields.toList()..sort(),
    'baseRev': baseRev,
    'version': version,
    'attempts': attempts,
    'state': state.name,
    'lastError': lastError,
    'notBefore': notBefore,
    'sent': sent,
  };

  @override
  String toString() =>
      'OutboxEntry(#$id ${op.name} $table/$rowId base=$baseRev v$version ${state.name})';
}

/// The result of folding a new local write into what is already queued.
sealed class Coalesced {
  const Coalesced();
}

/// Queue (or replace with) this entry.
final class Enqueue extends Coalesced {
  const Enqueue(this.entry);
  final OutboxEntry entry;
}

/// The change cancels out entirely: a row created and deleted before it was
/// ever pushed. Remove the pending entry; nothing reaches the server.
final class Cancel extends Coalesced {
  const Cancel(this.entryId);
  final int entryId;
}

abstract final class Outbox {
  /// Folds a new local [op] on a row into its [pending] entry, if any.
  ///
  /// * upsert after upsert → one upsert with the newest payload and the UNION
  ///   of changed fields, still based on the original base revision;
  /// * delete after a never-pushed create → [Cancel] (nothing to tell the
  ///   server; gravity_brew instead retried a delete of a missing row forever);
  /// * delete after an upsert of a server row → one delete at the same base;
  /// * upsert after a delete → one upsert (the row is resurrected).
  ///
  /// A dead entry is replaced by the new change, pending again: the user has
  /// written the row anew, so the old failure no longer describes it.
  static Coalesced coalesce({
    required OutboxEntry? pending,
    required int newId,
    required String table,
    required String rowId,
    required OutboxOp op,
    required Map<String, Object?> payload,
    required Set<String> changedFields,
    required int? baseRev,
  }) {
    if (pending == null) {
      return Enqueue(
        OutboxEntry(
          id: newId,
          table: table,
          rowId: rowId,
          op: op,
          payload: payload,
          changedFields: changedFields,
          baseRev: baseRev,
          version: 1,
        ),
      );
    }
    if (op == OutboxOp.delete && pending.isCreate && !pending.sent) {
      return Cancel(pending.id);
    }
    return Enqueue(
      pending.copyWith(
        op: op,
        payload: payload,
        changedFields: {...pending.changedFields, ...changedFields},
        version: pending.version + 1,
        attempts: 0,
        state: OutboxState.pending,
        clearNotBefore: true,
      ),
    );
  }
}
