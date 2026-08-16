import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Reported by crawler-m3b, 2026-08-14: invite redemption returned 403 forever.
// The row rule guarding it was correct, the SQL was correct, and the request
// was refused anyway.
//
// A row rule decides whether the RESULTING row is allowed, so it is handed a
// `before` and an `after`. `after` is computed by replaying a `List<Update>`
// over `before`. For a plain update that list is the caller's and everything
// lines up. For a CUSTOM operation it is the server's: `custom()` returns a
// whole query, and the caller of a redemption sends no updates at all -- the
// increment is the server's own and deliberately not theirs to influence.
//
// So `after` came back a copy of `before`, `useCount` never moved, and a rule
// written to permit exactly the computed result refused every call. Nothing was
// available locally to suggest which of the three correct-looking pieces was
// lying.
//
// The fix is `TableOperations.customUpdates`: the operations half declares what
// it is going to write, and that declaration travels to the rules half on the
// response. It is simulated, never executed -- `custom()` remains the only
// thing that writes.

class _Invite {
  const _Invite({required this.id, this.useCount = 0, this.maxUses = 1});

  final int? id;
  final int useCount;
  final int maxUses;
}

class _InviteTable extends Table<_Invite> {
  _InviteTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      useCount = $.integer('use_count', (s) => s.useCount),
      maxUses = $.integer('max_uses', (s) => s.maxUses);

  @override
  _Invite fromRow(RowReader read) =>
      _Invite(id: read(id), useCount: read(useCount)!, maxUses: read(maxUses)!);

  final ColumnType<int?> id;
  final ColumnType<int> useCount;
  final ColumnType<int> maxUses;
}

final invites = sqliteTable('custom_op_invites', _InviteTable.new);

const _redeem = 'redeem';
const _relabel = 'relabel';

/// The single source both halves read.
///
/// Written once and used by `custom` and `customUpdates` alike, because
/// nothing checks that a declaration matches the query it describes -- and a
/// declaration that drifts makes the rule adjudicate a row the database will
/// never hold.
List<Update> _redeemUpdates() => [
  Update.column('use_count', const Increment()),
];

/// An operation whose write is the server's own idea.
///
/// `customUpdates` declares the same `Increment` the query performs. The two
/// live in one class, next to each other, which is the cheapest way to keep a
/// declaration honest — nothing checks that they agree, and a drifting
/// declaration makes the rule adjudicate the wrong row.
final class _InviteOperations extends TableOperations<_InviteTable, _Invite> {
  _InviteOperations() : super(invites);

  @override
  ToQuery<Schema<_Invite>, _Invite> custom(
    String operation, {
    Where? where,
    List<Update> updates = const [],
  }) {
    if (operation == _redeem) {
      return update(
        _redeemUpdates(),
        where: where ?? const Eq('id', -1),
      ).returning();
    }
    if (operation == _relabel) {
      // Writes exactly what it was handed, so it needs no declaration.
      return update(updates, where: where ?? const Eq('id', -1)).returning();
    }
    return super.custom(operation, where: where, updates: updates);
  }

  @override
  List<Update> customUpdates(
    String operation, {
    Where? where,
    List<Update> updates = const [],
  }) {
    if (operation == _redeem) return _redeemUpdates();
    return super.customUpdates(operation, where: where, updates: updates);
  }
}

/// An operation that writes, and never says so. The trap, kept in the suite on
/// purpose so the warning it triggers has something to fire on.
final class _SilentOperations extends TableOperations<_InviteTable, _Invite> {
  _SilentOperations() : super(invites);

  @override
  ToQuery<Schema<_Invite>, _Invite> custom(
    String operation, {
    Where? where,
    List<Update> updates = const [],
  }) =>
      update(_redeemUpdates(), where: where ?? const Eq('id', -1)).returning();
}

/// Permits the computed result and denies anything else -- the shape the report
/// asked for, because a rule that merely permits everything would pass whether
/// or not `after` was ever computed.
class _InviteRowRules extends RowRules<_InviteTable, _Invite> {
  const _InviteRowRules(super.schema);

  @override
  Map<String, CustomRowOperationRule<_Invite>> get customOperations => {
    _redeem: (jwt, before, after) async =>
        after.useCount == before.useCount + 1 &&
        after.useCount <= before.maxUses,
  };
}

Future<PerformOperationResponse> _resolve(
  DbOperations ops,
  CustomOperationRequest request,
) async {
  final response = await ops.dispatch(request);
  return response! as PerformOperationResponse;
}

void main() {
  group('a custom operation declares what it writes', () {
    late DbOperations ops;

    setUp(() {
      ops = DbOperations(operations: [_InviteOperations()], tables: [invites]);
    });

    test('the declared updates ride back on the response, so the rules half '
        'can see writes it has no other way to learn about', () async {
      final response = await _resolve(
        ops,
        CustomOperationRequest(
          table: 'custom_op_invites',
          operation: _redeem,
          where: const Eq('id', 1),
          // What a redeeming caller actually sends: nothing.
          updates: const [],
          jwt: null,
        ),
      );

      expect(response.updates, hasLength(1));
      expect(
        response.updates.single,
        isA<ColumnUpdate>()
            .having((u) => u.column, 'column', 'use_count')
            .having((u) => u.value, 'value', isA<Increment>()),
      );
    });

    test(
      'they survive the JSON round trip -- the two halves are separate '
      'workers, so anything that does not serialize is lost in transit',
      () async {
        final response = await _resolve(
          ops,
          CustomOperationRequest(
            table: 'custom_op_invites',
            operation: _redeem,
            where: const Eq('id', 1),
            updates: const [],
            jwt: null,
          ),
        );

        final revived = PerformOperationResponse.fromJson(response.toJson());

        expect(revived.updates, hasLength(1));
        expect(
          (revived.updates.single as ColumnUpdate).value,
          isA<Increment>(),
          reason:
              'the declaration is only useful on the far side of the wire; a '
              'field that survives in-process and not over IPC would pass every '
              'unit test here and fail in every real server',
        );
      },
    );

    test('a built-in operation declares nothing -- its updates already travel '
        'on the request', () async {
      final response = await ops.dispatch(
        UpdateOperationRequest(
          table: 'custom_op_invites',
          where: const Eq('id', 1),
          updates: [Update.column('use_count', const Literal(7))],
          jwt: null,
        ),
      );

      expect((response! as PerformOperationResponse).updates, isEmpty);
    });

    test('an operation that writes only what it was handed needs no '
        'declaration -- the default echoes the caller, so this mechanism stays '
        'invisible to every operation that never needed it', () async {
      final response = await _resolve(
        ops,
        CustomOperationRequest(
          table: 'custom_op_invites',
          operation: _relabel,
          where: const Eq('id', 1),
          updates: [Update.column('use_count', const Literal(3))],
          jwt: null,
        ),
      );

      expect(response.updates, hasLength(1));
      expect(
        (response.updates.single as ColumnUpdate).value,
        isA<Literal>(),
        reason:
            'no customUpdates override on this branch, and the caller update '
            'still reaches the rule -- the behaviour every existing custom '
            'operation had before this change',
      );
    });
  });

  group(
    'the row rule then adjudicates the row that will actually be written',
    () {
      late DbRules rules;
      late DbOperations ops;

      setUp(() {
        rules = DbRules(rules: [_InviteRowRules(invites)]);
        ops = DbOperations(
          operations: [_InviteOperations()],
          tables: [invites],
        );
      });

      Future<bool> canRedeem(Map<String, Object?> row) async {
        final operation = await _resolve(
          ops,
          CustomOperationRequest(
            table: 'custom_op_invites',
            operation: _redeem,
            where: const Eq('id', 1),
            updates: const [],
            jwt: null,
          ),
        );

        final response = await rules.dispatch(
          RowRulesRequest(
            table: 'custom_op_invites',
            operation: _redeem,
            data: row,
            // The connective tissue, and the whole fix: what the operation says
            // it will write, not what the caller proposed. `ZonaiDb.custom`
            // resolves the operation before the row checks for exactly this.
            updates: operation.updates,
            jwt: null,
          ),
        );

        return (response! as RowRulesResponse).canPerform;
      }

      test('a redemption within the use limit is PERMITTED -- the 403 that '
          'started this report', () async {
        expect(
          await canRedeem({'id': 1, 'use_count': 0, 'max_uses': 1}),
          isTrue,
          reason:
              'before the fix `after` was a copy of `before`, so use_count read '
              '0 where the rule required 1, and every redemption was refused',
        );
      });

      test(
        'a redemption that would exceed the use limit is still DENIED -- the '
        'rule is being evaluated, not bypassed',
        () async {
          expect(
            await canRedeem({'id': 1, 'use_count': 1, 'max_uses': 1}),
            isFalse,
            reason:
                'a fix that made every custom operation pass would satisfy the '
                'test above and be strictly worse than the bug',
          );
        },
      );
    },
  );

  group('an operation that writes without declaring it', () {
    test(
      'is warned about rather than silently deciding on an unchanged row',
      () async {
        final ops = DbOperations(
          operations: [_SilentOperations()],
          tables: [invites],
        );

        final operation = await _resolve(
          ops,
          CustomOperationRequest(
            table: 'custom_op_invites',
            operation: _redeem,
            where: const Eq('id', 1),
            updates: const [],
            jwt: null,
          ),
        );

        expect(
          operation.updates,
          isEmpty,
          reason: 'nothing declared, and nothing sent by the caller',
        );

        final rules = DbRules(rules: [_InviteRowRules(invites)]);
        final response = await rules.dispatch(
          RowRulesRequest(
            table: 'custom_op_invites',
            operation: _redeem,
            data: {'id': 1, 'use_count': 0, 'max_uses': 1},
            updates: operation.updates,
            jwt: null,
          ),
        );

        // The denial itself is correct and unavoidable: with nothing to replay,
        // `after` genuinely equals `before`, and this rule genuinely rejects
        // that row. What changed is that it is no longer silent -- a warning
        // naming the table, the operation and `customUpdates` is emitted once
        // per pair. This asserts the deny; the warning is verified by reading
        // the log, which this suite has no transport for.
        expect((response! as RowRulesResponse).canPerform, isFalse);
      },
    );
  });
}
