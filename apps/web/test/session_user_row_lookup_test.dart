import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/providers/pending_row_detail_provider.dart';
import 'package:zonai_web/providers/sqlite_tables_provider.dart';
import 'package:zonai_web/providers/table_row_detail_provider.dart';
import 'package:zonai_web/utils/session_user_row_lookup.dart';

ColumnShape _column(String name, {ColumnShapeKind kind = ColumnShapeKind.text, bool isPrimaryKey = false}) {
  return ColumnShape(
    name: name,
    kind: kind,
    isNullable: false,
    isPrimaryKey: isPrimaryKey,
    autoIncrement: false,
    sqlType: 'TEXT',
  );
}

TableSchemaShape _authSchema(String table, {String idColumn = 'id'}) {
  return TableSchemaShape(
    table: table,
    columns: [
      _column(idColumn, kind: ColumnShapeKind.id, isPrimaryKey: true),
      _column('email', kind: ColumnShapeKind.email),
      _column('is_verified', kind: ColumnShapeKind.isVerified),
    ],
  );
}

TableSchemaShape _plainSchema(String table) {
  return TableSchemaShape(
    table: table,
    columns: [
      _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
      _column('title'),
    ],
  );
}

SqliteTableRef _ref(String name, {bool isView = false}) =>
    SqliteTableRef(sqliteName: name, displayName: name, isView: isView);

void main() {
  group('sessionUserLookupCandidates', () {
    test('picks auth collections and names their primary key', () {
      final candidates = sessionUserLookupCandidates(
        schemas: {'users': _authSchema('users'), 'posts': _plainSchema('posts')},
        tables: [_ref('posts'), _ref('users')],
      );

      expect(candidates, [const SessionUserLookupCandidate(sqliteName: 'users', idColumn: 'id')]);
    });

    test('probes in sidebar order, not schema-map order', () {
      final candidates = sessionUserLookupCandidates(
        schemas: {'admins': _authSchema('admins'), 'users': _authSchema('users')},
        tables: [_ref('users'), _ref('admins')],
      );

      expect(candidates.map((c) => c.sqliteName), ['users', 'admins']);
    });

    test('uses the table\'s own primary key column name', () {
      final candidates = sessionUserLookupCandidates(
        schemas: {'members': _authSchema('members', idColumn: 'member_id')},
        tables: [_ref('members')],
      );

      expect(candidates.single.idColumn, 'member_id');
    });

    test('drops an auth collection with no sidebar entry', () {
      // No sidebar entry means no table route, and the row-detail panel is
      // only mounted on that route.
      final candidates = sessionUserLookupCandidates(schemas: {'users': _authSchema('users')}, tables: []);

      expect(candidates, isEmpty);
    });

    test('drops an auth collection with no schema', () {
      final candidates = sessionUserLookupCandidates(schemas: const {}, tables: [_ref('users')]);

      expect(candidates, isEmpty);
    });

    test('drops views', () {
      final viewSchema = TableSchemaShape(
        table: 'active_users',
        columns: _authSchema('active_users').columns,
        isView: true,
      );

      expect(
        sessionUserLookupCandidates(schemas: {'active_users': viewSchema}, tables: [_ref('active_users')]),
        isEmpty,
      );
      expect(
        sessionUserLookupCandidates(
          schemas: {'active_users': _authSchema('active_users')},
          tables: [_ref('active_users', isView: true)],
        ),
        isEmpty,
      );
    });

    test('drops a composite primary key, which a lone user_id cannot match', () {
      final schema = TableSchemaShape(
        table: 'memberships',
        columns: [
          _column('user_id', isPrimaryKey: true),
          _column('org_id', isPrimaryKey: true),
          _column('is_verified', kind: ColumnShapeKind.isVerified),
        ],
      );

      expect(sessionUserLookupCandidates(schemas: {'memberships': schema}, tables: [_ref('memberships')]), isEmpty);
    });

    test('drops a table with no primary key at all', () {
      final schema = TableSchemaShape(
        table: 'ghosts',
        columns: [
          _column('user_id'),
          _column('is_verified', kind: ColumnShapeKind.isVerified),
        ],
      );

      expect(sessionUserLookupCandidates(schemas: {'ghosts': schema}, tables: [_ref('ghosts')]), isEmpty);
    });
  });

  group('pendingRowDetailState', () {
    final pending = PendingRowDetail(
      sqliteName: 'users',
      rowKey: 'users/u_1',
      row: const ['u_1', 'a@b.c'],
      columns: const ['id', 'email'],
      columnShapes: [
        _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
        _column('email'),
      ],
    );

    test('opens on its own table', () {
      final state = pendingRowDetailState(focus: _ref('users'), pending: pending);

      expect(state?.sqliteName, 'users');
      expect(state?.rowKey, 'users/u_1');
      expect(state?.row, ['u_1', 'a@b.c']);
      expect(state?.columns, ['id', 'email']);
      expect(state?.viewMode, TableRowDetailViewMode.fields);
    });

    test('stays shut on another table', () {
      // A row from one collection inside another collection's panel would be
      // edited and deleted against the focused collection's permissions.
      expect(pendingRowDetailState(focus: _ref('posts'), pending: pending), isNull);
    });

    test('stays shut with no focus and with nothing pending', () {
      expect(pendingRowDetailState(focus: null, pending: pending), isNull);
      expect(pendingRowDetailState(focus: _ref('users'), pending: null), isNull);
    });

    test('copies the row, so editing the panel cannot write back through it', () {
      final state = pendingRowDetailState(focus: _ref('users'), pending: pending)!;

      expect(identical(state.row, pending.row), isFalse);
    });
  });
}
