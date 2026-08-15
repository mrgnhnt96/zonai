part of '../message_handler.dart';

typedef _EnqueuePushFn =
    Future<PushJobId> Function(
      PushMessage message, {
      required String table,
      required String column,
      Where? where,
    });

final _pushProvider = create<_Push>(_Push._);

/// Sends a notification to every row of [table] whose `deviceToken` [column]
/// matches [where].
///
/// Returns as soon as the job is **durably recorded**, carrying its id — not
/// when the notification was delivered, and not when the fan-out finished.
/// Query the `_push_jobs` collection with the id for progress, counts and
/// failure reasons.
///
/// ```dart no-analyze
/// final job = await push(
///   PushMessage(title: 'Reply', body: 'Someone replied to you'),
///   table: 'device_tokens',
///   column: 'token',
///   where: In('user_id', recipientIds),
/// );
/// ```
///
/// Call this from `after*` hooks, never `before*`: a `before` hook runs prior
/// to the write, and a notification announcing something that may not happen
/// cannot be recalled.
_Push get push => read(_pushProvider);

class _Push {
  _Push._() : _enqueue = _unavailable;

  const _Push(this._enqueue);

  final _EnqueuePushFn _enqueue;

  static Future<PushJobId> _unavailable(
    PushMessage message, {
    required String table,
    required String column,
    Where? where,
  }) async {
    throw StateError(
      'push is not available outside a request scope — call it from an '
      'extension hook or a cron job',
    );
  }

  Future<PushJobId> call(
    PushMessage message, {
    required String table,
    required String column,
    Where? where,
  }) => _enqueue(message, table: table, column: column, where: where);
}
