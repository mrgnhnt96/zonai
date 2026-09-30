import 'package:meta/meta.dart';
import 'package:zonai_sync/src/engine.dart' show SyncEngine;
import 'package:zonai_sync/src/outbox.dart';

enum SyncPhase {
  idle,
  pushing,
  pulling,

  /// No connection; local work continues and is queued.
  offline,

  /// The session expired (401). Nothing syncs until [SyncEngine.resume].
  needsAuth,

  /// No account is signed in.
  signedOut,
}

@immutable
final class SyncStatus {
  const SyncStatus({
    required this.phase,
    required this.pending,
    required this.deadLetters,
    this.lastSyncedAt,
    this.lastError,
    this.unclaimed = 0,
  });

  static const initial = SyncStatus(
    phase: SyncPhase.idle,
    pending: 0,
    deadLetters: [],
  );

  final SyncPhase phase;

  /// Local changes not yet on the server.
  final int pending;

  /// Changes the server refused for good. Show them; let the user retry or
  /// discard. Never silently dropped.
  final List<OutboxEntry> deadLetters;

  /// Device-clock time of the last complete sync — for display only, never
  /// for ordering.
  final DateTime? lastSyncedAt;
  final String? lastError;

  /// Local rows that name another owner (not one of [SyncEngine.guestIds]),
  /// so were never uploaded. They are kept on the device, unsynced — never
  /// deleted — for the app to resolve. Counted from the store at each pass's
  /// first sign-in or launch, so it survives restarts and clears with the
  /// rows.
  final int unclaimed;

  bool get isSynced =>
      pending == 0 && deadLetters.isEmpty && phase == SyncPhase.idle;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? pending,
    List<OutboxEntry>? deadLetters,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
    int? unclaimed,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    pending: pending ?? this.pending,
    deadLetters: deadLetters ?? this.deadLetters,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastError: clearError ? null : lastError ?? this.lastError,
    unclaimed: unclaimed ?? this.unclaimed,
  );

  @override
  String toString() =>
      'SyncStatus(${phase.name}, pending $pending, dead ${deadLetters.length})';
}
