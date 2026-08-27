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
enum CleanupAction { reclaimSpace, purgeLogs, purgeTable, cleanupPhotos }

/// The schema the application's own tables live in.
///
/// Written out rather than imported: the engine's schema constants live in
/// `apps/zonai`, behind an import chain that reaches native SQLite, and this
/// library compiles to JavaScript — the same reason [kReclaimableSchemas] is
/// a written-out copy. Drift is pinned by a test that walks
/// [kReclaimableSchemas] and requires a specific phrase for every member.
///
/// It is singled out because it is the one target whose rewrite blocks
/// *application* writes, which is what makes it the one that has to be
/// confirmed by name.
const kApplicationSchema = 'main';

/// The floor the Maintenance screen asks for when an operator presses Run:
/// none at all.
///
/// The engine's `kCronReclaimFloorBytes` is right for a nightly unattended
/// job, which should not take an exclusive lock to recover a few pages nobody
/// asked about. It is wrong for a human who is looking at "9.5 MB reclaimable"
/// on this very screen and presses the button — they would get a silent skip
/// for exactly the case they pressed it for. The floor became a parameter of
/// the engine call precisely so this call site could be zero.
const kUiReclaimFloorBytes = 0;

/// One database file the reclaim card can aim at.
///
/// Built from a [StorageDatabaseFile] rather than hardcoded, so the card
/// offers the real files of *this* deployment, with the real numbers that make
/// one of them worth picking.
final class ReclaimTarget {
  const ReclaimTarget({
    required this.schema,
    required this.name,
    required this.sizeBytes,
    required this.reclaimableBytes,
  });

  /// The schema identifier the request carries — a member of
  /// [kReclaimableSchemas].
  ///
  /// This, never [name] and never a path. [name] is a basename a project can
  /// configure, so picking a file out of the report by what its name contains
  /// matches on a coincidence rather than on identity.
  final String schema;

  /// The file's basename, which is what an operator recognises.
  final String name;

  /// Size of the file. The lock's duration scales with this, not with the
  /// freelist, so it is this number the disclosure quotes.
  final int sizeBytes;

  /// Bytes on this file's freelist, or `null` when the pragmas could not be
  /// read — unknown, never zero.
  final int? reclaimableBytes;

  /// What the dropdown shows: the file, and the reason to pick it.
  ///
  /// The reclaimable figure is in the label because it is the only thing that
  /// distinguishes one option from another for the purpose of this button. A
  /// list of three bare file names asks the operator to already know which one
  /// has dead space in it.
  String get label => '$name — ${formatOptionalBytes(reclaimableBytes)} reclaimable';
}

/// The database files the reclaim dropdown offers, in the report's own order.
///
/// A function rather than an inline loop so there is one thing to point a test
/// at, the same way [purgeableTableOptions] is one.
///
/// The order is the storage report's, which is application database first and
/// deterministic (the endpoint builds it from a fixed schema list). Left
/// alone rather than sorted, so the dropdown lists the files in the same order
/// as the "Database files" panel above it on the same screen.
///
/// Entries whose schema is not in [kReclaimableSchemas] are dropped: the
/// server validates [ReclaimTarget.schema] against that same set and would
/// refuse them, and an option that is guaranteed to fail is worse than no
/// option. Today the report only ever emits members of it, so this filter
/// removes nothing — it is what keeps that true.
List<ReclaimTarget> reclaimTargetOptions(StorageMetrics? metrics) {
  return [
    for (final db in metrics?.databases ?? const <StorageDatabaseFile>[])
      if (kReclaimableSchemas.contains(db.schema))
        ReclaimTarget(schema: db.schema, name: db.name, sizeBytes: db.sizeBytes, reclaimableBytes: db.reclaimableBytes),
  ];
}

/// What the operator must type to arm the reclaim, or `null` for a target that
/// needs no confirmation.
///
/// Per target, not per card. The card carried no confirmation at all while it
/// could only ever rewrite the log database, and the justification was
/// specific to that: safe from data loss precisely because the log database is
/// a file of its own. That reasoning does not survive generalisation. A
/// `VACUUM` on the application database takes an exclusive lock on
/// *application* data, and every write blocks for its duration — so
/// [kApplicationSchema] asks for the file's own name, and the other targets
/// stay as they were.
///
/// The file's name rather than a fixed phrase, for the reason the purge
/// dropdown uses the table's: it is the one string that cannot be
/// muscle-memoried from a different target.
String? reclaimConfirmPhrase(ReclaimTarget? target) {
  if (target == null) return null;
  return target.schema == kApplicationSchema ? target.name : null;
}

/// What one finished action did, in words an operator can act on.
///
/// [isSkip] is carried separately from the text so the UI can style a skip
/// differently from a success without re-parsing the sentence.
final class CleanupOutcome {
  const CleanupOutcome({required this.text, this.isSkip = false});

  final String text;
  final bool isSkip;
}

/// Which writes stall while [schema]'s file is being rewritten.
///
/// A clause of its own because it is one of the two things in
/// [describeReclaimLock] that the generalised card made target-specific: the
/// sentence used to say "log writes" unconditionally, which is simply false
/// for the application database.
///
/// The fallback is reachable only for a schema the server would refuse
/// anyway, and it names the stall vaguely rather than wrongly. A test walks
/// [kReclaimableSchemas] and requires each member to have a phrase of its own,
/// so a new reclaimable schema cannot quietly land on it.
String reclaimBlockedWrites(String schema) => switch (schema) {
  kApplicationSchema => 'application writes',
  'logdb' => 'log writes',
  'ratedb' => 'rate-limit writes',
  _ => 'writes to that database',
};

/// What the reclaim card says before the storage report has arrived.
///
/// There is no target yet, so there is no file to name and no size to quote.
/// It says what the verb does and what it costs — which is true of every
/// target — and stops there. The same instinct as the absent size
/// parenthetical: a card that reads correctly beats one padded out with
/// "unknown" in the places it does not know yet.
const kReclaimPendingDescription =
    'Rewrites a database file around its live pages, handing the dead ones back to the operating '
    'system. Locks the file it rewrites, and writes to that database block until it finishes. '
    'Pick a file once the storage report has loaded.';

/// The reclaim card's whole disclosure, lock first.
///
/// This sentence is the main thing standing between an operator and the
/// consequence — for [kApplicationSchema] a typed confirmation now stands
/// beside it, but for the other targets it is still the whole of it. That puts
/// two demands on it, and both survive the card becoming target-picking.
///
/// The lock leads. It is the only effect of pressing the button that cannot
/// be undone by waiting, and the reassurance either side of it — what gets
/// rewritten, what is not touched — is exactly the sort of thing that, read
/// first, makes a warning read last.
///
/// The size travels with it. The stall scales with the file, so "locks a
/// 20 KB file" and "locks a 3 GB file" are one sentence describing opposite
/// decisions, and an operator cannot weigh a duration nobody quotes. A
/// [ReclaimTarget] always has a size — it comes from the storage report, which
/// measures the file — so the "unknown size" case is now exactly the case
/// where there is no target at all, and it is answered by
/// [kReclaimPendingDescription] rather than by an absent parenthetical.
///
/// What changed for the generalisation is the two target-specific clauses.
/// "Log writes block" became [reclaimBlockedWrites], and "the application
/// database is not touched" — false when the application database is the
/// target — became a closing clause that reassures for the other schemas and
/// warns for this one.
String describeReclaimLock(ReclaimTarget? target) {
  if (target == null) return kReclaimPendingDescription;

  // Data safety is true of every target: a rewrite moves no rows, it only
  // closes the gaps the already-deleted ones left. What differs is blast
  // radius, so that is what the clause after it carries.
  final closing = target.schema == kApplicationSchema
      ? 'No rows are deleted, but this is the application database — every write to it waits.'
      : 'No rows are deleted, and the application database is not touched.';

  return 'Locks ${target.name} (${formatBytes(target.sizeBytes)}) while it rewrites; '
      '${reclaimBlockedWrites(target.schema)} block until it finishes. '
      'Space freed by deleted rows then goes back to the operating system. '
      '$closing';
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

/// Which database a result is about, in words rather than a schema id.
///
/// The payload's `target` is `main`/`logdb`/`ratedb`, which is the right thing
/// on the wire and the wrong thing in a sentence an operator reads. Mapped
/// here rather than looked up in the storage report on purpose: the report can
/// refresh between the request and the outcome being read, and a result must
/// keep describing the file it actually acted on.
///
/// An unrecognised identifier is quoted rather than dropped — it still names
/// which file the numbers are about, which is the entire reason `target` is on
/// the payload.
String reclaimTargetLabel(String schema) => switch (schema) {
  kApplicationSchema => 'the application database',
  'logdb' => 'the log database',
  'ratedb' => 'the rate-limit database',
  _ => 'the "$schema" database',
};

/// What a reclaim attempt did — including, verbatim, why it did nothing, and
/// which database it did it to.
///
/// **Every branch names the target.** A result stays on screen after it
/// arrives and the operator can move the picker while it is still there;
/// without the name, "0 B reclaimed" from the log database reads as a report
/// about whatever is now selected. The name comes from
/// [SpaceReclamationResult.target], which is the request's own answer rather
/// than the picker's current one.
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
///  * **Nothing worth doing.** The freelist was under the floor *this run
///    asked for*, so the engine did not bother. Phrased against the floor the
///    caller sent rather than against a fixed threshold, because there is no
///    longer a fixed one: the screen sends [kUiReclaimFloorBytes], which is
///    zero, and the engine's test is `reclaimable < floor`. Nothing is under
///    zero, so this branch cannot be reached from the Maintenance card at all
///    — an empty freelist gets a real (and near-instant) rewrite instead. It
///    stays because this function renders a payload, and the payload can still
///    represent it; it must not be a sentence that becomes false when it is.
///  * **Rewritten.** The bytes actually handed back to the operating system.
CleanupOutcome describeReclamation(SpaceReclamationResult result) {
  final target = reclaimTargetLabel(result.target);

  if (result.skipped case final reason?) {
    return CleanupOutcome(
      text:
          'Skipped $target: $reason. '
          '${formatBytes(result.reclaimableBytes)} are still on the freelist.',
      isSkip: true,
    );
  }

  if (!result.vacuumed) {
    return CleanupOutcome(
      text:
          'Nothing rewritten in $target — '
          '${formatBytes(result.reclaimableBytes)} on the freelist was under '
          'the floor this run asked for.',
    );
  }

  return CleanupOutcome(
    text:
        '${formatBytes(result.reclaimedBytes)} returned to the operating '
        'system from $target '
        '(${formatBytes(result.reclaimableBytes)} was on the freelist).',
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

  /// Rewrites [target]'s database file, with no floor.
  ///
  /// [target] is a schema identifier, never a path — see [ReclaimTarget.schema]
  /// for why the browser must not be the one naming a file. The server
  /// validates it against [kReclaimableSchemas] regardless of what is sent.
  Future<void> reclaimSpace({required String target}) {
    return _run(CleanupAction.reclaimSpace, (server) async {
      return describeReclamation(
        await api.reclaimSpace(server: server, target: target, minReclaimableBytes: kUiReclaimFloorBytes),
      );
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
