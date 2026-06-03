import 'package:raindrop/raindrop.dart' hide Table, Update;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

class _Row {
  const _Row({
    this.id,
    required this.title,
    this.qty = 100,
    this.tags = const [],
  });

  final int? id;
  final String title;
  final int qty;
  final List<String> tags;
}

class _TestTable extends Table<_Row> {
  _TestTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      title = $.text('title', (s) => s.title),
      qty = $.integer('qty', (s) => s.qty),
      tags = $.list(
        'tags',
        (s) => s.tags,
        fromJson: (e) => switch (e) {
          String() => e,
          _ => '$e',
        },
      );

  @override
  _Row fromRow(RowReader read) => _Row(
    id: read(id),
    title: read(title)!,
    qty: read(qty)!,
    tags: read(tags)!,
  );

  final IntColumn id;

  final TextColumn title;

  final IntColumn qty;

  final ListColumn<String> tags;
}

class _JsonRow {
  const _JsonRow({this.id, required this.title, this.profile = const {}});

  final int? id;
  final String title;
  final Map<String, dynamic> profile;
}

class _JsonTable extends Table<_JsonRow> {
  _JsonTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      title = $.text('title', (s) => s.title),
      profile = $.map('profile', (s) => s.profile);

  @override
  _JsonRow fromRow(RowReader read) =>
      _JsonRow(id: read(id), title: read(title)!, profile: read(profile)!);

  final IntColumn id;

  final TextColumn title;

  final MapColumn profile;
}

final jsonWidgets = sqliteTable('json_widgets', _JsonTable.new);

final class _JsonOperations
    extends TableOperations<_JsonTable, _JsonRow> {
  _JsonOperations() : super(jsonWidgets);
}

class _Profile {
  const _Profile({this.displayName, this.role});

  final String? displayName;
  final String? role;

  factory _Profile.fromJson(dynamic json) {
    final m = Map<String, dynamic>.from(json as Map);
    return _Profile(
      displayName: m['displayName'] as String?,
      role: m['role'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'displayName': displayName, 'role': role};
}

class _TypedJsonRow {
  const _TypedJsonRow({
    this.id,
    required this.title,
    this.profile = const _Profile(),
  });

  final int? id;
  final String title;
  final _Profile profile;
}

class _TypedJsonTable extends Table<_TypedJsonRow> {
  _TypedJsonTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      title = $.text('title', (s) => s.title),
      profile = $.mapAs(
        'profile',
        (s) => s.profile,
        fromJson: _Profile.fromJson,
        synthetic: const _Profile(),
      );

  @override
  _TypedJsonRow fromRow(RowReader read) =>
      _TypedJsonRow(id: read(id), title: read(title)!, profile: read(profile)!);

  final IntColumn id;

  final TextColumn title;

  final TypedMapColumn<_Profile> profile;
}

final typedJsonWidgets = sqliteTable(
  'typed_json_widgets',
  _TypedJsonTable.new,
);

final class _TypedJsonOperations
    extends TableOperations<_TypedJsonTable, _TypedJsonRow> {
  _TypedJsonOperations() : super(typedJsonWidgets);
}

final widgets = sqliteTable('widgets', _TestTable.new);

final class _Operations extends TableOperations<_TestTable, _Row> {
  _Operations() : super(widgets);
}

void main() {
  final ops = _Operations();
  const dialect = SQLiteDialect();

  group('TableOperations query builders', () {
    test('insert builds translatable INSERT … RETURNING query', () {
      final query = ops.insert({
        'title': 'hello',
        'qty': 100,
        'tags': '[]',
      }).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('INSERT INTO "widgets"'));
      expect(sql.toUpperCase(), contains('RETURNING'));
      expect(sql, contains('"title"'));
      expect(sql, contains('"qty"'));
      expect(sql, contains('"tags"'));
    });

    test('insertMany builds translatable INSERT … RETURNING query', () {
      final query = ops.insertMany([
        const _Row(title: 'a'),
        const _Row(title: 'b'),
      ]).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('INSERT INTO "widgets"'));
      expect(sql.toUpperCase(), contains('RETURNING'));
    });

    test('update builds translatable UPDATE with WHERE from Where', () {
      final query = ops.update([
        Update.column('title', const Literal('renamed')),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('UPDATE "widgets"'));
      expect(sql.toUpperCase(), contains('SET'));
      expect(sql, contains('WHERE'));
      expect(sql, contains('"widgets"."id" = 1'));
    });

    test('update applies increment expression for Increment value', () {
      final query = ops.update([
        Update.column('id', const Increment()),
      ], where: const Eq('title', 'x')).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('UPDATE "widgets"'));
      expect(sql, contains('"id"'));
      expect(sql, contains('+'));
    });

    test('update applies decrement expression for Decrement value', () {
      final query = ops.update([
        Update.column('qty', const Decrement()),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('UPDATE "widgets"'));
      expect(sql, contains('"qty"'));
      expect(sql, contains('-'));
    });

    test('update applies add expression for Add value', () {
      final query = ops.update([
        Update.column('qty', const Add(5)),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('UPDATE "widgets"'));
      expect(sql, contains('"qty"'));
      expect(sql, contains('+'));
    });

    test('update applies remove expression for Remove value', () {
      final query = ops.update([
        Update.column('qty', const Remove(3)),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('UPDATE "widgets"'));
      expect(sql, contains('"qty"'));
      expect(sql, contains('-'));
    });

    test('update Add on json list column uses json_insert', () {
      final query = ops.update([
        Update.column('tags', const Add('x')),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('json_insert'));
      expect(sql, contains('"tags"'));
    });

    test('update Remove on json list column filters with json_each', () {
      final query = ops.update([
        Update.column('tags', const Remove('x')),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('json_each'));
      expect(sql, contains('json_group_array'));
    });

    test('update AddAll on list column merges arrays', () {
      final query = ops.update([
        Update.column('tags', const AddAll(['x', 'y'])),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql.toUpperCase(), contains('UNION ALL'));
      expect(sql, contains('json_each'));
      expect(sql, contains('json_group_array'));
    });

    test('update RemoveAll on list column uses NOT IN json_each', () {
      final query = ops.update([
        Update.column('tags', const RemoveAll(['x', 'z'])),
      ], where: const Eq('id', 1)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql.toUpperCase(), contains('NOT IN'));
      expect(sql, contains('json_each'));
      expect(sql, contains('json_group_array'));
    });

    group('jsonMap column updates', () {
      final jsonOps = _JsonOperations();
      final typedOps = _TypedJsonOperations();

      test('nested ColumnUpdate path uses json_set on jsonMap column', () {
        final query = jsonOps.update([
          Update.column('profile.displayName', const Literal('Pat')),
        ], where: const Eq('id', 1)).toQuery();
        final (sql, _) = dialect.translate(query);
        expect(sql, contains('json_set'));
        expect(sql, contains('"profile"'));
      });

      test('nested ColumnUpdate path uses json_set on mapAs column', () {
        final query = typedOps.update([
          Update.column('profile.displayName', const Literal('Pat')),
        ], where: const Eq('id', 1)).toQuery();
        final (sql, _) = dialect.translate(query);
        expect(sql, contains('json_set'));
        expect(sql, contains('"profile"'));
      });

      test('ObjectUpdate with plain map merges via json_patch', () {
        final query = jsonOps.update([
          Update.object({
            'profile': {'displayName': 'Pat', 'age': 30},
          }),
        ], where: const Eq('id', 1)).toQuery();
        final (sql, _) = dialect.translate(query);
        expect(sql, contains('json_patch'));
        expect(sql, contains('"profile"'));
      });

      test('dotted column on non-jsonMap column throws', () {
        expect(
          () => ops.update([
            Update.column('title.suffix', const Literal('x')),
          ], where: const Eq('id', 1)).toQuery(),
          throwsArgumentError,
        );
      });
    });

    test('AddAll on non-list column throws', () {
      expect(
        () => ops.update([
          Update.column('qty', const AddAll([1, 2])),
        ], where: const Eq('id', 1)).toQuery(),
        throwsArgumentError,
      );
    });

    test('RemoveAll on non-list column throws', () {
      expect(
        () => ops.update([
          Update.column('qty', const RemoveAll([1])),
        ], where: const Eq('id', 1)).toQuery(),
        throwsArgumentError,
      );
    });

    test('count builds translatable SELECT COUNT … query', () {
      final query = ops.count().toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql.toUpperCase(), contains('COUNT'));
      expect(sql, contains('FROM "widgets"'));
    });

    test('count withWhere adds WHERE clause', () {
      final query = ops.count(where: const Eq('title', 't')).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql.toUpperCase(), contains('COUNT'));
      expect(sql, contains('WHERE'));
      expect(sql, contains('"widgets"."title" = \'t\''));
    });

    test('list builds translatable SELECT with limit and offset', () {
      final query = ops
          .list(where: const Gt('id', 0), limit: 10, offset: 5)
          .toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('FROM "widgets"'));
      expect(sql.toUpperCase(), contains('LIMIT'));
      expect(sql.toUpperCase(), contains('OFFSET'));
    });

    test('list with groupBy builds translatable SELECT', () {
      final query = ops.list(groupBy: widgets.title).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql.toUpperCase(), contains('GROUP BY'));
      expect(sql, contains('"title"'));
    });

    test('delete builds translatable DELETE with WHERE', () {
      final query = ops.delete(const Eq('id', 2)).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('DELETE FROM "widgets"'));
      expect(sql, contains('WHERE'));
    });

    test('delete with limit applies LIMIT', () {
      final query = ops.delete(const Eq('title', 'z'), limit: 3).toQuery();
      final (sql, _) = dialect.translate(query);
      expect(sql, contains('DELETE FROM "widgets"'));
      expect(sql.toUpperCase(), contains('LIMIT'));
    });

    test('custom throws UnimplementedError', () {
      expect(
        () => ops.custom('unknown_op').toQuery(),
        throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('unknown_op'),
          ),
        ),
      );
    });
  });

  group('TableOperations SQLite execution', () {
    late Raindrop memoryDb;
    late _Operations execOps;

    setUp(() async {
      memoryDb = Raindrop(SQLiteDelegate.memory());
      execOps = _Operations();
      execOps.db = memoryDb;
      await memoryDb.ensureOpen();
      await memoryDb.execute(
        'CREATE TABLE "widgets" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"title" TEXT NOT NULL, '
        '"qty" INTEGER NOT NULL DEFAULT 100, '
        '"tags" TEXT NOT NULL DEFAULT \'[]\''
        ');',
        const [],
      );
    });

    tearDown(() async {
      await memoryDb.close();
    });

    test('insert with returning rows', () async {
      final inserted = await execOps.insert({
        'title': 'one',
        'qty': 100,
        'tags': '[]',
      });
      expect(inserted, hasLength(1));
      expect(inserted.single.id, isNotNull);
      expect(inserted.single.title, 'one');
      expect(inserted.single.qty, 100);
      expect(inserted.single.tags, isEmpty);
      expect(await execOps.count().single, 1);
    });

    test('insertMany with returning rows', () async {
      final inserted = await execOps.insertMany([
        const _Row(title: 'a'),
        const _Row(title: 'b'),
      ]);
      expect(inserted, hasLength(2));
      expect(inserted.map((r) => r.title).toList()..sort(), ['a', 'b']);
      expect(await execOps.count().single, 2);
    });

    test('count with where', () async {
      await execOps.insertMany([
        const _Row(title: 'keep'),
        const _Row(title: 'drop'),
      ]);
      expect(await execOps.count(where: const Eq('title', 'keep')).single, 1);
      expect(await execOps.count().single, 2);
    });

    test('list with where respects limit', () async {
      for (var i = 0; i < 5; i++) {
        await execOps.insert({'title': 'row_$i', 'qty': 100, 'tags': '[]'});
      }
      final page = await execOps.list(where: const Gt('id', 0), limit: 2);
      expect(page, hasLength(2));
    });

    test('list groupBy runs successfully', () async {
      await execOps.insert({'title': 'g', 'qty': 1, 'tags': '[]'});
      await execOps.insert({'title': 'g', 'qty': 1, 'tags': '[]'});
      final rows = await execOps.list(groupBy: widgets.title);
      expect(rows, isNotEmpty);
    });

    test('update mutates matching rows', () async {
      await execOps.insert({'title': 'old', 'qty': 100, 'tags': '[]'});
      await execOps.update([
        Update.column('title', const Literal('new')),
      ], where: const Eq('title', 'old'));
      expect(await execOps.count(where: const Eq('title', 'new')).single, 1);
      expect(await execOps.count(where: const Eq('title', 'old')).single, 0);
    });

    test('delete removes matching rows', () async {
      await execOps.insert({'title': 'gone', 'qty': 1, 'tags': '[]'});
      await execOps.insert({'title': 'stay', 'qty': 1, 'tags': '[]'});
      await execOps.delete(const Eq('title', 'gone'));
      expect(await execOps.count().single, 1);
      expect(await execOps.count(where: const Eq('title', 'stay')).single, 1);
    });

    test('delete with limit only removes some matches', () async {
      await execOps.insert({'title': 'z', 'qty': 1, 'tags': '[]'});
      await execOps.insert({'title': 'z', 'qty': 1, 'tags': '[]'});
      await execOps.insert({'title': 'z', 'qty': 1, 'tags': '[]'});
      await execOps.delete(const Eq('title', 'z'), limit: 2);
      expect(await execOps.count(where: const Eq('title', 'z')).single, 1);
    });

    group('UpdateValue SQLite execution', () {
      test('Literal updates integer column', () async {
        await execOps.insert({'title': 'v-lit', 'qty': 1, 'tags': '[]'});
        await execOps.update([
          Update.column('qty', const Literal(42)),
        ], where: const Eq('title', 'v-lit'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-lit'),
        )).single;
        expect(row.qty, 42);
      });

      test('Increment adds one', () async {
        await execOps.insert({'title': 'v-inc', 'qty': 10, 'tags': '[]'});
        await execOps.update([
          Update.column('qty', const Increment()),
        ], where: const Eq('title', 'v-inc'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-inc'),
        )).single;
        expect(row.qty, 11);
      });

      test('Decrement subtracts one', () async {
        await execOps.insert({'title': 'v-dec', 'qty': 10, 'tags': '[]'});
        await execOps.update([
          Update.column('qty', const Decrement()),
        ], where: const Eq('title', 'v-dec'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-dec'),
        )).single;
        expect(row.qty, 9);
      });

      test('Add increases by operand', () async {
        await execOps.insert({'title': 'v-add', 'qty': 10, 'tags': '[]'});
        await execOps.update([
          Update.column('qty', const Add(7)),
        ], where: const Eq('title', 'v-add'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-add'),
        )).single;
        expect(row.qty, 17);
      });

      test('Remove decreases by operand', () async {
        await execOps.insert({'title': 'v-rem', 'qty': 10, 'tags': '[]'});
        await execOps.update([
          Update.column('qty', const Remove(3)),
        ], where: const Eq('title', 'v-rem'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-rem'),
        )).single;
        expect(row.qty, 7);
      });

      test('Add appends to JSON list column', () async {
        await execOps.insert({
          'title': 'v-tags-add',
          'qty': 1,
          'tags': '["a"]',
        });
        await execOps.update([
          Update.column('tags', const Add('b')),
        ], where: const Eq('title', 'v-tags-add'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-tags-add'),
        )).single;
        expect(row.tags, ['a', 'b']);
      });

      test('Remove drops matching values from JSON list column', () async {
        await execOps.insert({
          'title': 'v-tags-rm',
          'qty': 1,
          'tags': '["a","b","a"]',
        });
        await execOps.update([
          Update.column('tags', const Remove('a')),
        ], where: const Eq('title', 'v-tags-rm'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-tags-rm'),
        )).single;
        expect(row.tags, ['b']);
      });

      test('AddAll appends multiple values to JSON list column', () async {
        await execOps.insert({
          'title': 'v-tags-add-all',
          'qty': 1,
          'tags': '["a"]',
        });
        await execOps.update([
          Update.column('tags', const AddAll(['b', 'c'])),
        ], where: const Eq('title', 'v-tags-add-all'));
        final row = (await execOps.list(
          where: const Eq('title', 'v-tags-add-all'),
        )).single;
        expect(row.tags, ['a', 'b', 'c']);
      });

      test(
        'RemoveAll drops every listed value from JSON list column',
        () async {
          await execOps.insert({
            'title': 'v-tags-rm-all',
            'qty': 1,
            'tags': '["a","b","c","a"]',
          });
          await execOps.update([
            Update.column('tags', const RemoveAll(['a', 'c'])),
          ], where: const Eq('title', 'v-tags-rm-all'));
          final row = (await execOps.list(
            where: const Eq('title', 'v-tags-rm-all'),
          )).single;
          expect(row.tags, ['b']);
        },
      );
    });

    group('jsonMap column execution', () {
      late Raindrop memoryDb;
      late _JsonOperations execJsonOps;

      setUp(() async {
        memoryDb = Raindrop(SQLiteDelegate.memory());
        execJsonOps = _JsonOperations();
        execJsonOps.db = memoryDb;
        await memoryDb.ensureOpen();
        await memoryDb.execute(
          'CREATE TABLE "json_widgets" ('
          '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"title" TEXT NOT NULL, '
          '"profile" TEXT NOT NULL DEFAULT \'{}\''
          ');',
          const [],
        );
      });

      tearDown(() async {
        await memoryDb.close();
      });

      test('ColumnUpdate dotted path sets nested key only', () async {
        await execJsonOps.insert({
          'title': 'jm1',
          'profile': {'displayName': 'Old', 'role': 'user'},
        });
        await execJsonOps.update([
          Update.column('profile.displayName', const Literal('New')),
        ], where: const Eq('title', 'jm1'));
        final row = (await execJsonOps.list(
          where: const Eq('title', 'jm1'),
        )).single;
        expect(row.profile['displayName'], 'New');
        expect(row.profile['role'], 'user');
      });

      test('ObjectUpdate plain map merges into jsonMap', () async {
        await execJsonOps.insert({
          'title': 'jm2',
          'profile': {'displayName': 'Old', 'role': 'user'},
        });
        await execJsonOps.update([
          Update.object({
            'profile': {'displayName': 'Merged'},
          }),
        ], where: const Eq('title', 'jm2'));
        final row = (await execJsonOps.list(
          where: const Eq('title', 'jm2'),
        )).single;
        expect(row.profile['displayName'], 'Merged');
        expect(row.profile['role'], 'user');
      });

      test('ColumnUpdate without dots replaces entire jsonMap', () async {
        await execJsonOps.insert({
          'title': 'jm3',
          'profile': {'a': 1},
        });
        await execJsonOps.update([
          Update.column('profile', const Literal({'b': 2})),
        ], where: const Eq('title', 'jm3'));
        final row = (await execJsonOps.list(
          where: const Eq('title', 'jm3'),
        )).single;
        expect(row.profile, {'b': 2});
      });
    });

    group('mapAs column execution', () {
      late Raindrop memoryDb;
      late _TypedJsonOperations execTypedOps;

      setUp(() async {
        memoryDb = Raindrop(SQLiteDelegate.memory());
        execTypedOps = _TypedJsonOperations();
        execTypedOps.db = memoryDb;
        await memoryDb.ensureOpen();
        await memoryDb.execute(
          'CREATE TABLE "typed_json_widgets" ('
          '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"title" TEXT NOT NULL, '
          '"profile" TEXT NOT NULL DEFAULT \'{}\''
          ');',
          const [],
        );
      });

      tearDown(() async {
        await memoryDb.close();
      });

      test(
        'Profile decodes from insert; dotted path update re-decodes',
        () async {
          await execTypedOps.insert({
            'title': 'tp1',
            'profile': {'displayName': 'Old', 'role': 'user'},
          });
          await execTypedOps.update([
            Update.column('profile.displayName', const Literal('New')),
          ], where: const Eq('title', 'tp1'));
          final row = (await execTypedOps.list(
            where: const Eq('title', 'tp1'),
          )).single;
          expect(row.profile.displayName, 'New');
          expect(row.profile.role, 'user');
        },
      );
    });
  });
}
