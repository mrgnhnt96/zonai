import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

// Prefixed: the notifier's methods are named after the verbs they run, so an
// unprefixed import would have every call site shadowed by the method calling
// it.
import '../api/maintenance_client.dart' as api;
import '../utils/user_facing_error.dart';
import 'toast_provider.dart';

/// Storage usage, loaded client-side.
///
/// Not polled: collection is expensive (a `df` spawn, a recursive walk of the
/// photos directory, two pragma round trips per database file), and disk usage
/// does not move on the timescale a poll would catch. It refreshes when an
/// operator asks it to.
final storageMetricsProvider = AsyncNotifierProvider<StorageMetricsNotifier, StorageMetrics?>(
  StorageMetricsNotifier.new,
);

class StorageMetricsNotifier extends AsyncNotifier<StorageMetrics?> {
  @override
  Future<StorageMetrics?> build() async {
    // SSR has no frames, so an async provider that completes after the server
    // render has nothing to notify (see the comment in dashboard_screen.dart).
    if (!ref.binding.isClient) return null;

    return await api.fetchStorageMetrics(server: ref.read(revaliServerProvider));
  }

  void refresh() => ref.invalidateSelf();
}

/// How a byte count renders when the number is not known.
///
/// `freeDiskBytes` returns `null` for *unknown* and never zero — an unparsed
/// `df` and a full disk are opposite situations. Rendering unknown as "0 B"
/// would report an emergency that is not happening, while hiding that the
/// value was never read, so unknown gets a word of its own.
const kUnknownSize = 'unknown';

/// [formatBytes] for a known count, [kUnknownSize] for `null`.
String formatOptionalBytes(int? bytes) => bytes == null ? kUnknownSize : formatBytes(bytes);

// ── Cleanup actions ───────────────────────────────────────────────────────────

/// The destructive verbs on the Maintenance screen.
///
/// An enum rather than free strings so the running-state map, the confirm
/// state and the outcome map cannot disagree about which button is which.
enum CleanupAction { reclaimLogSpace, purgeLogs, purgeTable, cleanupPhotos }

/// What one finished action did, in words an operator can act on.
///
/// [isSkip] is carried separately from the text so the UI can style a skip
/// differently from a success without re-parsing the sentence.
final class CleanupOutcome {
  const CleanupOutcome({required this.text, this.isSkip = false});

  final String text;
  final bool isSkip;
}

/// The reclaim card's whole disclosure, lock first.
///
/// Reclaim is the one cleanup action with no typed confirmation, because it
/// destroys nothing — so this sentence is the entire thing standing between
/// an operator and the consequence. That puts two demands on it.
///
/// The lock leads. It is the only effect of pressing the button that cannot
/// be undone by waiting, and the reassurance either side of it — what gets
/// rewritten, what is not touched — is exactly the sort of thing that, read
/// first, makes a warning read last.
///
/// The size travels with it. The stall scales with the file, so "locks a
/// 20 KB file" and "locks a 3 GB file" are one sentence describing opposite
/// decisions, and an operator cannot weigh a duration nobody quotes. Before
/// the storage report lands [bytes] is null and the parenthetical is simply
/// absent: the sentence still reads correctly, and "(unknown)" would draw the
/// eye to the one part that does not matter yet.
String describeReclaimLock({required String file, required int? bytes}) {
  final size = bytes == null ? '' : ' (${formatBytes(bytes)})';
  return 'Locks $file$size while it rewrites; log writes block until it finishes. '
      'Space freed by deleted rows then goes back to the operating system. '
      'The application database is not touched.';
}

/// Rows removed, said plainly — including when the answer is none.
///
/// "Nothing to delete" rather than "0 rows deleted": a purge that matched
/// nothing is the common, healthy result, and phrasing it as a count reads
/// like a failure. The count is still exact when there is one, because "some
/// rows" is not an answer an operator can compare against a row total.
String describeRowsPurged(int rows, {required String noun}) {
  if (rows == 0) return 'Nothing to delete — no $noun matched';
  return '$rows ${rows == 1 ? noun.replaceAll(RegExp(r's$'), '') : noun} deleted';
}

/// What the photo sweep did.
String describePhotoCleanup(int deleted) {
  if (deleted == 0) return 'Nothing to delete — every photo is still referenced';
  return '$deleted unreferenced photo${deleted == 1 ? '' : 's'} deleted, files and all';
}

/// What a reclaim attempt did — including, verbatim, why it did nothing.
///
/// The three outcomes are deliberately three different sentences:
///
///  * **Skipped.** The reason string is reproduced word for word. This is the
///    case the field exists for: a deployment whose volume is already full
///    fails the headroom check and reclaims nothing, and a silent success
///    there is indistinguishable from having had nothing to reclaim. The
///    reclaimable figure rides along, because "0 B reclaimed" alone would
///    read as "nothing to do" in exactly the situation where there is a lot
///    to do and no room to do it in.
///  * **Nothing worth doing.** Below the engine's floor, so it did not bother.
///    Not a problem, and phrased so it does not look like one.
///  * **Rewritten.** The bytes actually handed back to the operating system.
CleanupOutcome describeReclamation(LogSpaceReclamationResult result) {
  if (result.skipped case final reason?) {
    return CleanupOutcome(
      text:
          'Skipped: $reason. '
          '${formatBytes(result.reclaimableBytes)} are still on the freelist.',
      isSkip: true,
    );
  }

  if (!result.vacuumed) {
    return CleanupOutcome(
      text:
          'Nothing worth reclaiming — '
          '${formatBytes(result.reclaimableBytes)} on the freelist is under '
          'the threshold for a rewrite.',
    );
  }

  return CleanupOutcome(
    text:
        '${formatBytes(result.reclaimedBytes)} returned to the operating '
        'system (${formatBytes(result.reclaimableBytes)} was on the freelist).',
  );
}

/// The tables the purge dropdown offers, in a stable order.
///
/// A function rather than the raw set so there is one thing to point a test
/// at: "`_photos` is not in the dropdown" is a claim about *this* list, and a
/// test against [kPurgeableTableNames] would only be a claim about the set the
/// list happens to be built from today.
List<String> purgeableTableOptions() => kPurgeableTableNames.toList()..sort();

/// Whether a typed confirmation matches what the button asked for.
///
/// Case-insensitive and trimmed — the point of the typed confirm is to make
/// the operator name the thing they are about to empty, not to test their
/// shift key.
bool cleanupConfirmMatches({required String typed, required String expected}) {
  return typed.trim().toLowerCase() == expected.trim().toLowerCase();
}

/// Which action is running, and what the last one did.
final cleanupActionsProvider = NotifierProvider<CleanupActionsNotifier, CleanupActionsState>(
  CleanupActionsNotifier.new,
);

final class CleanupActionsState {
  const CleanupActionsState({this.running, this.outcomes = const {}});

  /// The action currently in flight, or `null`.
  ///
  /// One at a time: every one of these serializes against writes in the engine
  /// anyway, and a screen with three spinners invites an operator to queue a
  /// vacuum behind a purge without meaning to.
  final CleanupAction? running;

  /// The most recent outcome per action, kept until the action is run again.
  final Map<CleanupAction, CleanupOutcome> outcomes;

  bool get isBusy => running != null;

  CleanupActionsState copyWith({
    CleanupAction? running,
    bool clearRunning = false,
    Map<CleanupAction, CleanupOutcome>? outcomes,
  }) {
    return CleanupActionsState(
      running: clearRunning ? null : (running ?? this.running),
      outcomes: outcomes ?? this.outcomes,
    );
  }
}

class CleanupActionsNotifier extends Notifier<CleanupActionsState> {
  @override
  CleanupActionsState build() => const CleanupActionsState();

  Future<void> reclaimLogSpace() {
    return _run(CleanupAction.reclaimLogSpace, (server) async {
      return describeReclamation(await api.reclaimLogSpace(server: server));
    });
  }

  Future<void> purgeLogs({required int? olderThanDays}) {
    return _run(CleanupAction.purgeLogs, (server) async {
      final result = await api.purgeLogs(server: server, olderThanDays: olderThanDays);
      return CleanupOutcome(text: describeRowsPurged(result.rowsAffected, noun: 'log rows'));
    });
  }

  Future<void> purgeTable({required String table}) {
    return _run(CleanupAction.purgeTable, (server) async {
      final result = await api.purgeInternalTable(server: server, table: table);
      return CleanupOutcome(text: '$table: ${describeRowsPurged(result.rowsAffected, noun: 'rows')}');
    });
  }

  Future<void> cleanupPhotos() {
    return _run(CleanupAction.cleanupPhotos, (server) async {
      final result = await api.cleanupUnreferencedPhotos(server: server);
      return CleanupOutcome(text: describePhotoCleanup(result.deletedCount));
    });
  }

  Future<void> _run(CleanupAction action, Future<CleanupOutcome> Function(Server server) call) async {
    if (state.isBusy) return;

    state = state.copyWith(running: action);
    try {
      final outcome = await call(ref.read(revaliServerProvider));

      state = CleanupActionsState(outcomes: {...state.outcomes, action: outcome});

      // The numbers the operator is looking at are now wrong. Refreshing is
      // the point of having run this at all -- a purge that reports "4.6M rows
      // deleted" above a storage panel still showing 4.6M rows reads as a
      // failure.
      ref.read(storageMetricsProvider.notifier).refresh();

      if (outcome.isSkip) {
        ref.read(toastProvider.notifier).showError(outcome.text);
      } else {
        ref.read(toastProvider.notifier).showSuccess(outcome.text);
      }
    } catch (error) {
      state = state.copyWith(clearRunning: true);
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    }
  }
}
