import 'package:meta/meta.dart';
import 'package:zonai_sync/src/remote.dart';

enum SyncMode {
  bidirectional,

  /// Server-authored data the client must never write (e.g. memberships a
  /// client could otherwise mark "active" itself).
  pullOnly,

  /// Client-authored data never read back (e.g. analytics events).
  pushOnly,
}

/// What wins when a push finds the server row has moved past the revision the
/// local change was based on. Ordering is by server revision only — never by
/// comparing a device clock with the server's (gravity_brew bug class #4).
sealed class ConflictPolicy {
  const ConflictPolicy();

  /// Keep the server row; drop the local change.
  static const serverWins = ServerWins();

  /// Re-apply the whole local row on top of the server's.
  static const clientWins = ClientWins();

  /// Re-apply only the fields changed locally; keep the server's other fields.
  /// The default: two devices editing different fields both keep their edit.
  static const fieldMerge = FieldMerge();
}

final class ServerWins extends ConflictPolicy {
  const ServerWins();
}

final class ClientWins extends ConflictPolicy {
  const ClientWins();
}

final class FieldMerge extends ConflictPolicy {
  const FieldMerge();
}

/// Resolve with app logic. Return the row to write back, or null to accept
/// the server's row.
final class CustomMerge extends ConflictPolicy {
  const CustomMerge(this.resolve);

  final Map<String, Object?>? Function({
    required Map<String, Object?> local,
    required RemoteRow server,
    required Set<String> changedFields,
  })
  resolve;
}

/// Describes one synced table.
@immutable
final class SyncTable {
  const SyncTable(
    this.name, {
    this.scopeColumn = 'owner_id',
    this.mode = SyncMode.bidirectional,
    this.parents = const [],
    this.references = const {},
    this.conflict = ConflictPolicy.fieldMerge,
  });

  /// The zonai table name.
  final String name;

  /// Column holding the owner's user id; every pull is filtered by it. Null
  /// for tables every signed-in user may read in full.
  final String? scopeColumn;
  final SyncMode mode;

  /// Tables whose rows this table references. Their changes are pushed and
  /// pulled first, so a child never reaches the server before its parent.
  final List<String> parents;

  /// Foreign keys as `column -> parent table`. When given, a child row is held
  /// back only while ITS parent row is stuck (queued, backing off, or dead);
  /// without them, any stuck row in a parent table holds back the whole child
  /// table.
  final Map<String, String> references;
  final ConflictPolicy conflict;

  bool get pushes => mode != SyncMode.pullOnly;
  bool get pulls => mode != SyncMode.pushOnly;
}

/// Orders [tables] parents-first. Throws on unknown parents or cycles.
List<SyncTable> orderTables(List<SyncTable> tables) {
  final byName = {for (final t in tables) t.name: t};
  final ordered = <SyncTable>[];
  final state = <String, int>{}; // 1 visiting, 2 done
  void visit(SyncTable t, List<String> path) {
    if (state[t.name] == 2) return;
    if (state[t.name] == 1) {
      throw StateError(
        'Sync tables form a cycle: ${[...path, t.name].join(' -> ')}',
      );
    }
    state[t.name] = 1;
    for (final MapEntry(key: column, value: target) in t.references.entries) {
      // A referenced table must also be a parent, or nothing orders it
      // first and the child is pushed ahead of the row it points at. A
      // self-reference is exempt: rows of one table go out in outbox order,
      // and the per-row hold keeps a child behind a stuck parent row.
      if (target != t.name && !t.parents.contains(target)) {
        throw StateError(
          '${t.name}.$column references "$target", which is not in its '
          'parents',
        );
      }
    }
    for (final p in t.parents) {
      final parent = byName[p];
      if (parent == null) {
        throw StateError('${t.name} lists unknown parent table "$p"');
      }
      visit(parent, [...path, t.name]);
    }
    state[t.name] = 2;
    ordered.add(t);
  }

  for (final t in tables) {
    visit(t, const []);
  }
  return ordered;
}
