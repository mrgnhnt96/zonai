import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _Item {
  const _Item({required this.id, this.roles = const []});

  final int? id;
  final List<String> roles;
}

class _ItemTable extends Table<_Item> {
  _ItemTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      roles = $.list('roles', (s) => s.roles, fromJson: (e) => e as String);

  @override
  _Item fromRow(RowReader read) => _Item(id: read(id), roles: read(roles)!);

  final ColumnType<int?> id;
  final ListColumn<String> roles;
}

final items = sqliteTable('rules_items', _ItemTable.new);

/// Mirrors issue #23's motivating example: a rule that must see the row
/// `Add`/`AddAll` would actually produce, not a stale copy of `before`.
class _ItemRowRules extends RowRules<_ItemTable, _Item> {
  const _ItemRowRules(super.schema);

  @override
  Future<bool> canUpdate(Jwt? jwt, _Item before, _Item after) async {
    return !after.roles.contains('admin');
  }
}

void main() {
  late DbRules dbRules;

  setUp(() {
    dbRules = DbRules(rules: [_ItemRowRules(items)]);
  });

  group('DbRules row-level canUpdate before/after', () {
    test(
      'denies an Add("admin") update even though the pre-write row has no '
      'admin role — the exact privilege-escalation case from issue #23',
      () async {
        final response = await dbRules.dispatch(
          RowRulesRequest(
            table: 'rules_items',
            operation: RowOperation.update,
            data: {'id': 1, 'roles': '["member"]'},
            updates: [Update.column('roles', const Add('admin'))],
            jwt: null,
          ),
        );

        expect(response, isA<RowRulesResponse>());
        expect((response as RowRulesResponse).canPerform, isFalse);
      },
    );

    test('allows an update that does not grant admin', () async {
      final response = await dbRules.dispatch(
        RowRulesRequest(
          table: 'rules_items',
          operation: RowOperation.update,
          data: {'id': 1, 'roles': '["member"]'},
          updates: [Update.column('roles', const Add('editor'))],
          jwt: null,
        ),
      );

      expect(response, isA<RowRulesResponse>());
      expect((response as RowRulesResponse).canPerform, isTrue);
    });

    test('the batch path applies the same simulation per row', () async {
      final response = await dbRules.dispatch(
        BatchRowRulesRequest(
          table: 'rules_items',
          operation: RowOperation.update,
          rows: [
            {'id': 1, 'roles': '["member"]'},
            {'id': 2, 'roles': '["member"]'},
          ],
          updates: [
            Update.column('roles', const AddAll(['admin'])),
          ],
          jwt: null,
        ),
      );

      expect(response, isA<BatchRowRulesResponse>());
      expect((response as BatchRowRulesResponse).canPerform, [
        isFalse,
        isFalse,
      ]);
    });

    test('an empty updates list (non-update operations) leaves after '
        'identical to before', () async {
      final response = await dbRules.dispatch(
        RowRulesRequest(
          table: 'rules_items',
          operation: RowOperation.update,
          data: {'id': 1, 'roles': '["admin"]'},
          jwt: null,
        ),
      );

      // Pre-existing admin role in `before`/`after` (no updates touch it)
      // is still correctly denied — proves `after` isn't silently `true`.
      expect(response, isA<RowRulesResponse>());
      expect((response as RowRulesResponse).canPerform, isFalse);
    });
  });
}
