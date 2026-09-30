import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _Doc {
  const _Doc({required this.id, required this.ownerId});

  final int? id;
  final String ownerId;
}

class _DocTable extends Table<_Doc> {
  _DocTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      ownerId = $.text('owner_id', (s) => s.ownerId);

  @override
  _Doc fromRow(RowReader read) => _Doc(id: read(id), ownerId: read(ownerId));

  final ColumnType<int?> id;
  final TextColumn ownerId;
}

final docs = sqliteTable('scope_docs', _DocTable.new);

/// Every table-level answer is "yes", except that nobody may delete, so the
/// scope can be observed on a granted read and on a refusal.
final class _DocTableRules extends TableRules<_DocTable, _Doc> {
  const _DocTableRules(super.schema);

  @override
  Future<bool> canView(Jwt? jwt) async => true;
  @override
  Future<bool> canList(Jwt? jwt) async => true;
  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;
  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
  @override
  Future<bool> canDelete(Jwt? jwt) async => false;
}

final class _ScopedRowRules extends RowRules<_DocTable, _Doc> {
  const _ScopedRowRules(super.schema);

  static const scope = Eq('owner_id', 'u1');

  @override
  Future<Where?> viewScope(Jwt? jwt) async => scope;
}

/// Declares every row visible (`requiresPerRowCheck => false`) AND a scope.
/// The first statement is the stronger: a table whose rules already said
/// "every row" must not be narrowed by a scope it also happens to have --
/// an inherited default, say.
final class _EveryRowScopedRules extends _ScopedRowRules {
  const _EveryRowScopedRules(super.schema);

  @override
  bool get requiresPerRowCheck => false;
}

Future<TableRulesResponse> _ask(DbRules rules, String operation) async {
  final response = await rules.dispatch(
    TableRulesRequest(table: 'scope_docs', operation: operation, jwt: null),
  );
  return response! as TableRulesResponse;
}

void main() {
  group('TableRulesResponse.scope on the wire', () {
    test('a response from a worker that predates it reads as no scope', () {
      // Exactly what an old worker sends: no `scope` key at all.
      final response = TableRulesResponse.fromJson({
        'id': '1',
        'path': 'ignored',
        'table': 'scope_docs',
        'operation': 'list',
        'canAccess': true,
        'skipRowChecks': false,
      });

      expect(response.canAccess, isTrue);
      expect(response.scope, isNull);
    });

    test('a scope survives the round trip', () {
      final sent = TableRulesResponse(
        id: '1',
        table: 'scope_docs',
        operation: 'list',
        canAccess: true,
        scope: const And([Eq('owner_id', 'u1'), NotNull('id')]),
      );

      final received = TableRulesResponse.fromJson(sent.toJson());

      expect(received.scope?.toJson(), sent.scope!.toJson());
    });

    test('no scope sends no key', () {
      final json = TableRulesResponse(
        id: '1',
        table: 'scope_docs',
        operation: 'list',
        canAccess: true,
      ).toJson();

      expect(json.containsKey('scope'), isFalse);
    });
  });

  group('DbRules attaches viewScope', () {
    late DbRules rules;

    setUp(() {
      rules = DbRules(rules: [_DocTableRules(docs), _ScopedRowRules(docs)]);
    });

    for (final read in ['view', 'list', 'count']) {
      test('to a granted $read', () async {
        final response = await _ask(rules, read);

        expect(response.canAccess, isTrue);
        expect(response.scope?.toJson(), _ScopedRowRules.scope.toJson());
      });
    }

    test('not to a write', () async {
      final response = await _ask(rules, 'update');

      expect(response.canAccess, isTrue);
      expect(response.scope, isNull);
    });

    test('not to a refusal', () async {
      final response = await _ask(rules, 'delete');

      expect(response.canAccess, isFalse);
      expect(response.scope, isNull);
    });

    test('not when the row rules skip per-row checks', () async {
      final everyRow = DbRules(
        rules: [_DocTableRules(docs), _EveryRowScopedRules(docs)],
      );

      final response = await _ask(everyRow, 'list');

      expect(response.skipRowChecks, isTrue);
      expect(response.scope, isNull, reason: 'every row is visible');
    });

    test('and a row rule that declares none sends none', () async {
      final unscoped = DbRules(
        rules: [_DocTableRules(docs), RowRules<_DocTable, _Doc>(docs)],
      );

      final response = await _ask(unscoped, 'list');

      expect(response.canAccess, isTrue);
      expect(response.scope, isNull);
    });
  });
}
