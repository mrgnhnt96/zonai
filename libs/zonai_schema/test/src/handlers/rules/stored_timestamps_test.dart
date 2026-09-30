import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Issue #40: row rules were handed `created_at = now()` and a nullable
/// `updated_at = null` for rows that already exist, because the rules worker
/// rebuilt them with the create-time `safeCreate`. A rule reading either
/// timestamp -- "editable for 24h", "not updated since X" -- decided on values
/// that were never stored.

final class _Post {
  const _Post({required this.id, required this.createdAt, this.updatedAt});

  final int? id;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class _PostTable extends Table<_Post> {
  _PostTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  final ColumnType<int?> id;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;

  @override
  _Post fromRow(RowReader read) => _Post(
    id: read(id),
    createdAt: read(createdAt),
    updatedAt: read(updatedAt),
  );
}

final _posts = sqliteTable('stored_posts', _PostTable.new);

/// A table whose `created_at` is nullable: rows written before the column
/// existed hold NULL there.
final class _Legacy {
  const _Legacy({required this.id, this.createdAt});

  final int? id;
  final DateTime? createdAt;
}

final class _LegacyTable extends Table<_Legacy> {
  _LegacyTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  final ColumnType<int?> id;
  final ColumnType<DateTime?> createdAt;

  @override
  _Legacy fromRow(RowReader read) =>
      _Legacy(id: read(id), createdAt: read(createdAt));
}

final _legacy = sqliteTable('legacy_posts', _LegacyTable.new);

/// Records every row it is shown, and allows everything.
final class _SpyRowRules extends RowRules<_PostTable, _Post> {
  _SpyRowRules() : super(_posts);

  final seen = <_Post>[];

  @override
  Future<bool> canView(Jwt? jwt, _Post row) async {
    seen.add(row);
    return true;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, _Post row) async {
    seen.add(row);
    return true;
  }

  @override
  Future<bool> canUpdate(Jwt? jwt, _Post before, _Post after) async {
    seen
      ..add(before)
      ..add(after);
    return true;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, _Post row) async {
    seen.add(row);
    return true;
  }
}

/// Records the rows its update and delete hooks are shown.
final class _SpyExtension extends Extension<_Post> {
  _SpyExtension() : super(_posts);

  final seen = <_Post>[];

  @override
  Future<void> beforeCreate(_Post row, Jwt? jwt) async => seen.add(row);

  @override
  Future<void> beforeUpdate(_Post row, Jwt? jwt) async => seen.add(row);

  @override
  Future<void> afterUpdateSuccess(_Post before, _Post after, Jwt? jwt) async =>
      seen
        ..add(before)
        ..add(after);

  @override
  Future<void> afterDeleteSuccess(_Post row, Jwt? jwt) async => seen.add(row);
}

void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1790720125490);
  final updated = DateTime.fromMillisecondsSinceEpoch(1790720999000);
  final stored = {
    'id': 1,
    'created_at': created.millisecondsSinceEpoch,
    'updated_at': updated.millisecondsSinceEpoch,
  };

  late _SpyRowRules spy;
  late DbRules rules;

  setUp(() {
    spy = _SpyRowRules();
    rules = DbRules(rules: [spy]);
  });

  Future<void> ask(String operation, {List<Update> updates = const []}) async {
    final response = await rules.dispatch(
      RowRulesRequest(
        table: 'stored_posts',
        operation: operation,
        data: stored,
        updates: updates,
        jwt: null,
      ),
    );
    expect((response! as RowRulesResponse).canPerform, isTrue);
  }

  for (final operation in ['view', 'delete']) {
    test('$operation sees the stored timestamps', () async {
      await ask(operation);

      expect(spy.seen.single.createdAt, created);
      expect(spy.seen.single.updatedAt, updated);
    });
  }

  test('update sees them on before AND after', () async {
    await ask('update', updates: const []);

    final [before, after] = spy.seen;
    expect(before.createdAt, created);
    expect(before.updatedAt, updated);
    expect(
      after.createdAt,
      created,
      reason: 'an update cannot move created_at',
    );
  });

  test('batch view sees them too', () async {
    final response = await rules.dispatch(
      BatchRowRulesRequest(
        table: 'stored_posts',
        operation: 'view',
        rows: [stored],
        jwt: null,
      ),
    );

    expect((response! as BatchRowRulesResponse).canPerform, [true]);
    expect(spy.seen.single.createdAt, created);
    expect(spy.seen.single.updatedAt, updated);
  });

  group('extension hooks see stored timestamps too', () {
    late _SpyExtension hook;
    late DbExtensions extensions;

    setUp(() {
      hook = _SpyExtension();
      extensions = DbExtensions(extensions: [hook]);
    });

    test('beforeUpdate', () async {
      await extensions.dispatch(
        BeforeUpdateExtensionRequest(
          table: 'stored_posts',
          objects: [stored],
          jwt: null,
        ),
      );

      expect(hook.seen.single.createdAt, created);
      expect(hook.seen.single.updatedAt, updated);
    });

    test('afterUpdateSuccess, before and after', () async {
      await extensions.dispatch(
        AfterUpdateExtensionRequest(
          table: 'stored_posts',
          before: [stored],
          after: [stored],
          jwt: null,
        ),
      );

      for (final row in hook.seen) {
        expect(row.createdAt, created);
      }
    });

    test('afterDeleteSuccess', () async {
      await extensions.dispatch(
        DeleteExtensionRequest.afterSuccess(
          table: 'stored_posts',
          objects: [stored],
          jwt: null,
        ),
      );

      expect(hook.seen.single.createdAt, created);
    });
  });

  group('a create is stamped, whatever the client sent', () {
    final sent = {'created_at': 0};

    bool stampedNow(DateTime at) =>
        DateTime.now().difference(at).abs() < const Duration(minutes: 1);

    test('canCreate', () async {
      final response = await rules.dispatch(
        RowRulesRequest(
          table: 'stored_posts',
          operation: 'create',
          data: sent,
          updates: const [],
          jwt: null,
        ),
      );

      expect((response! as RowRulesResponse).canPerform, isTrue);
      expect(stampedNow(spy.seen.single.createdAt), isTrue);
    });

    test('beforeCreate', () async {
      final hook = _SpyExtension();
      await DbExtensions(extensions: [hook]).dispatch(
        CreateExtensionRequest.before(
          table: 'stored_posts',
          object: sent,
          jwt: null,
        ),
      );

      expect(stampedNow(hook.seen.single.createdAt), isTrue);
    });
  });

  test('a stored NULL in a nullable created_at stays NULL', () {
    final row = _legacy.$.safeCreate({
      'id': 1,
      'created_at': null,
    }, stored: true);

    expect(
      row.createdAt,
      isNull,
      reason: 'now() is not when this row was made',
    );
  });
}
