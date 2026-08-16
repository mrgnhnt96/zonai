import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A custom operation may not be named after a classic verb.
///
/// `RuleRequest.classicOperation` resolves an operation name to the built-in
/// [TableOperation]/[RowOperation] whenever one matches, and `DbRules` branches
/// on that before it ever looks in `customOperations`. So a rule registered as
/// `customOperations['update']` was unreachable: `canUpdate` decided the call
/// and the registered rule was never consulted — while reading, in the source,
/// exactly like a rule that was enforcing something.
///
/// That is the worst shape a security control can take, so this is refused when
/// the rules map is built rather than warned about per request.
class _NoteId implements Id {
  const _NoteId(this.value);

  @override
  final String value;
}

class _Note {
  const _Note({required this.id, required this.title});

  final _NoteId id;
  final String title;
}

final class _NoteTable extends Table<_Note> {
  _NoteTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _NoteId.new,
        generate: () => const _NoteId('generated'),
      ),
      title = $.text('title', (s) => s.title);

  @override
  _Note fromRow(RowReader read) => _Note(id: read(id), title: read(title)!);

  final IdColumn<_NoteId> id;
  final TextColumn title;
}

final notes = sqliteTable('notes', _NoteTable.new);

final class _PlainTableRules extends TableRules<_NoteTable, _Note> {
  _PlainTableRules() : super(notes);
}

final class _PlainRowRules extends RowRules<_NoteTable, _Note> {
  _PlainRowRules() : super(notes);
}

/// Registers a *table*-level custom operation under a classic verb's name.
final class _CollidingTableRules extends TableRules<_NoteTable, _Note> {
  _CollidingTableRules() : super(notes);

  @override
  Map<String, CustomTableOperationRule> get customOperations => {
    // Reads as "only an admin may update" and enforces nothing: every
    // `update` is decided by `canUpdate` below, which allows everyone.
    'update': (jwt) async => jwt?.admin.isAdmin == true,
  };

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;
}

/// Registers a *row*-level custom operation under a classic verb's name.
final class _CollidingRowRules extends RowRules<_NoteTable, _Note> {
  _CollidingRowRules() : super(notes);

  @override
  Map<String, CustomRowOperationRule<_Note>> get customOperations => {
    'view': (jwt, before, after) async => false,
  };
}

/// A custom operation under a name of its own — the shape that must keep working.
final class _WellNamedTableRules extends TableRules<_NoteTable, _Note> {
  _WellNamedTableRules() : super(notes);

  @override
  Map<String, CustomTableOperationRule> get customOperations => {
    'archive': (jwt) async => jwt != null,
  };
}

void main() {
  group('custom operation names may not collide with classic verbs', () {
    test('a table rule named after a classic verb is refused', () {
      final rules = DbRules(rules: [_CollidingTableRules(), _PlainRowRules()]);

      expect(
        () => rules.rulesByTable,
        throwsA(
          isA<CustomOperationNameCollisionException>()
              .having((e) => e.operation, 'operation', 'update')
              .having((e) => e.table, 'table', 'notes'),
        ),
      );
    });

    test('a row rule named after a classic verb is refused', () {
      final rules = DbRules(rules: [_PlainTableRules(), _CollidingRowRules()]);

      expect(
        () => rules.rulesByTable,
        throwsA(
          isA<CustomOperationNameCollisionException>().having(
            (e) => e.operation,
            'operation',
            'view',
          ),
        ),
      );
    });

    test('an operation with a name of its own still registers', () {
      final rules = DbRules(rules: [_WellNamedTableRules(), _PlainRowRules()]);

      expect(rules.rulesByTable.keys, contains('notes'));
      expect(rules.customTableOperationNames('notes'), {'archive'});
    });

    test('rules with no custom operations at all are unaffected', () {
      final rules = DbRules(rules: [_PlainTableRules(), _PlainRowRules()]);

      expect(rules.rulesByTable.keys, contains('notes'));
      expect(rules.customTableOperationNames('notes'), isEmpty);
    });
  });
}
