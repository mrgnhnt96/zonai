import 'package:test/test.dart';
import 'package:zonai/src/domain/gen/client_emitter.dart';
import 'package:zonai/src/domain/gen/client_names.dart';
import 'package:zonai/src/domain/gen/client_schema_document.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';
import 'package:zonai/src/domain/gen/dart_client_emitter.dart';
import 'package:zonai_schema/zonai_schema.dart'
    show ColumnShape, ColumnShapeKind, ForeignKeyShape, TableSchemaShape;

ColumnShape _column(
  String name, {
  ColumnShapeKind kind = ColumnShapeKind.text,
  bool isNullable = false,
  bool isPrimaryKey = false,
  bool isSecret = false,
  ForeignKeyShape? foreignKey,
}) {
  return ColumnShape(
    name: name,
    kind: kind,
    isNullable: isNullable,
    isPrimaryKey: isPrimaryKey,
    autoIncrement: false,
    sqlType: 'TEXT',
    isSecret: isSecret,
    foreignKey: foreignKey,
  );
}

/// A miniature of the playground's shape: a table with a foreign key, the
/// table it points at, a view, and a secret column.
final _shapes = <String, TableSchemaShape>{
  'authors': TableSchemaShape(
    table: 'authors',
    columns: [
      _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
      _column('name'),
    ],
  ),
  'post_summary': TableSchemaShape(
    table: 'post_summary',
    isView: true,
    columns: [
      _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
      _column('title'),
    ],
  ),
  'posts': TableSchemaShape(
    table: 'posts',
    columns: [
      _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
      _column(
        'author_id',
        kind: ColumnShapeKind.id,
        foreignKey: const ForeignKeyShape(table: 'authors', column: 'id'),
      ),
      _column('photo', kind: ColumnShapeKind.photo, isNullable: true),
      _column('draft_key', isSecret: true),
      _column('created_at', kind: ColumnShapeKind.createdAt),
    ],
  ),
};

Map<String, String> _emit({
  ClientSettings settings = const ClientSettings(output: 'gen/zonai'),
  Map<String, TableSchemaShape>? shapes,
}) {
  final schema = ClientSchemaDocument.fromShapes(shapes ?? _shapes);
  return const DartClientEmitter().emit(
    ClientGenerationInput(
      schema: schema,
      settings: settings,
      generatorVersion: '9.9.9',
    ),
  );
}

void main() {
  group('the file set', () {
    test('is a barrel, a shared runtime and one file per table', () {
      expect(
        _emit().keys.toList()..sort(),
        [
          'tables/authors.g.dart',
          'tables/post_summary.g.dart',
          'tables/posts.g.dart',
          DartClientEmitter.barrelFileName,
          DartClientEmitter.runtimeFileName,
        ]..sort(),
      );
    });

    test('every file carries the generated-code header', () {
      for (final entry in _emit().entries) {
        expect(
          entry.value,
          startsWith(kGeneratedClientHeader),
          reason: '${entry.key} is a file a human could open by mistake',
        );
      }
    });

    test('every file says that types are not permission', () {
      // §8.3. A typed API *reads* as a guarantee, and the file the developer
      // has open is where that misreading happens -- so it belongs here and
      // not only in the docs.
      for (final entry in _emit().entries) {
        expect(entry.value, contains('canView'), reason: entry.key);
        expect(entry.value, contains('reject at runtime'), reason: entry.key);
      }
    });

    test('is byte-identical run to run', () {
      expect(_emit(), _emit());
    });
  });

  group('the read model', () {
    test('decodes each kind to the Dart type §4.1 implies', () {
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, contains('final PostsId id;'));
      expect(posts, contains('final AuthorsId authorId;'));
      // §4.2: resolved URL on read, photo id on write. Phase 1 is read-only.
      expect(posts, contains('final Uri? photo;'));
      // §4.1: epoch milliseconds, not a DateTime on the wire.
      expect(posts, contains('final DateTime createdAt;'));
      expect(
        posts,
        contains("createdAt: _r.dateTime(json, 'created_at'"),
        reason: 'the wire key stays snake_case',
      );
    });

    test('gives a secret column no field at all', () {
      // §4.4: `_sanitizeRows` strips secrets from every response, so a
      // declared field would be null in every row that ever parses.
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, isNot(contains('draftKey')));
      expect(posts, isNot(contains("_r.string(json, 'draft_key'")));
      expect(
        posts,
        contains('`draft_key` is a secret column'),
        reason: 'absent is a decision, and the model should say so',
      );
    });

    test('types a foreign key by the table it points at', () {
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, contains("import 'authors.g.dart';"));
      expect(posts, contains("AuthorsId(_r.string(json, 'author_id'"));
    });

    test('nests expanded relations, keyed by the foreign-key column', () {
      // §4.3: `_expandRecord` writes to `row['expanded'][<fk column>]`.
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, contains('final class PostsExpanded'));
      expect(posts, contains('final AuthorsRow? authorId;'));
      expect(posts, contains("json['author_id']"));
      expect(posts, contains("PostsExpanded.tryFromJson(json['expanded'])"));
    });

    test('emits no expanded holder for a table with no foreign keys', () {
      final authors = _emit()['tables/authors.g.dart']!;

      expect(authors, isNot(contains('AuthorsExpanded')));
    });

    test('does not treat a photo column as an expandable relation', () {
      // A photo column has a foreign key into `_photos`, which is a table this
      // client never generates -- expanding it would yield an internal row.
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, isNot(contains('PhotosRow')));
    });
  });

  group('the API', () {
    test('offers get, list and count and nothing else', () {
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, contains('Future<PostsRow> get('));
      expect(posts, contains('Future<Paginated<PostsRow>> list({'));
      expect(posts, contains('Future<int> count({'));

      // Phase 2. Emitting them now would be a write surface with no builders.
      expect(posts, isNot(contains('Future<PostsRow> create')));
      expect(posts, isNot(contains('Future<void> delete')));
      expect(posts, isNot(contains('update(')));
    });

    test('takes an Authorization on every method, never a raw String', () {
      // §5.8: a bare JWT reaches the server without the `Bearer ` prefix and
      // is treated as *unauthenticated* rather than rejected, so the wrapper
      // is the point of the type.
      final posts = _emit()['tables/posts.g.dart']!;

      expect('Authorization? as'.allMatches(posts), hasLength(3));
      expect(posts, isNot(contains('String? authorization')));
      expect('authorization: as?.header,'.allMatches(posts), hasLength(3));
    });

    test('keys get by the typed id', () {
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, contains('PostsId id, {'));
      expect(posts, contains("where: Eq('id', id.value)"));
    });

    test('a view gets the same read surface and no more', () {
      // §8.4: views are read-only. Phase 1 emits only reads, so the rule costs
      // nothing yet -- but the file should say why.
      final view = _emit()['tables/post_summary.g.dart']!;

      expect(view, contains('read-only view'));
      expect(view, contains('Future<PostSummaryRow> get('));
      expect(view, contains('Future<int> count({'));
      expect(view, isNot(contains('create')));
    });
  });

  group('the expand example in list()', () {
    // Regression: this line used to be the literal
    // `['author_id', 'author_id.company_id']` for every table in every
    // project. Those are apps/playground's columns, so it read as correct
    // there and was wrong everywhere else -- including on tables with no
    // foreign keys, where it named a column the schema does not have. Found
    // by generating a client for a DIFFERENT project; the playground's own
    // goldens could not see it.
    test('names this table\'s own foreign key, not a fixed one', () {
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, contains("`['author_id']`"));
      expect(posts, isNot(contains('company_id')));
    });

    test('says so plainly when the table has no expandable relation', () {
      final authors = _emit()['tables/authors.g.dart']!;

      expect(authors, contains('`authors` has no foreign keys'));
      expect(authors, isNot(contains('author_id')));
    });

    test('never suggests a photo column, which cannot be expanded', () {
      // `photo` IS a foreign key, but it points at the `_photos` system table,
      // which is not generated -- so the generated `expanded` class has no
      // field for it. Reading foreign keys directly produced `['photo']` here;
      // deriving from ExpandBinding is what keeps the example and the
      // expanded class agreeing.
      final posts = _emit()['tables/posts.g.dart']!;

      expect(posts, isNot(contains("`['photo']`")));
    });

    test('chains a second hop only when the target has one', () {
      final shapes = <String, TableSchemaShape>{
        ..._shapes,
        'companies': TableSchemaShape(
          table: 'companies',
          columns: [
            _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
          ],
        ),
        'authors': TableSchemaShape(
          table: 'authors',
          columns: [
            _column('id', kind: ColumnShapeKind.id, isPrimaryKey: true),
            _column(
              'company_id',
              kind: ColumnShapeKind.id,
              foreignKey: const ForeignKeyShape(
                table: 'companies',
                column: 'id',
              ),
            ),
          ],
        ),
      };

      final posts = _emit(shapes: shapes)['tables/posts.g.dart']!;

      // Now that authors DOES have a foreign key, the dotted form appears --
      // which is the only reason the example exists.
      expect(posts, contains("`['author_id', 'author_id.company_id']`"));
    });
  });

  group('the barrel', () {
    test('hangs the tables off ZonaiClient as an extension', () {
      // §6: the dependency arrow points generated -> zonai_client, never back.
      final barrel = _emit()[DartClientEmitter.barrelFileName]!;

      expect(barrel, contains('extension ZonaiTables on ZonaiClient {'));
      expect(barrel, contains('PostsApi get posts => PostsApi(db);'));
      expect(barrel, contains('PostSummaryApi get postSummary'));
    });

    test('exports Authorization but not the parse helpers', () {
      final barrel = _emit()[DartClientEmitter.barrelFileName]!;

      expect(
        barrel,
        contains(
          "export '${DartClientEmitter.runtimeFileName}' "
          'show Authorization, ZonaiRowParseException;',
        ),
        reason: 'ZonaiRowReader is an implementation detail of the models',
      );
    });
  });

  group('naming', () {
    test('does not singularize', () {
      // §10.1: `posts` -> `PostsRow`, never `Post`. No English guessing.
      final names = TableNames.forTable('posts', const ClientSettings());

      expect(names.row, 'PostsRow');
      expect(names.id, 'PostsId');
      expect(names.api, 'PostsApi');
      expect(names.getter, 'posts');
    });

    test('converts snake_case consistently', () {
      expect(
        TableNames.forTable('cell_edit_fixtures', const ClientSettings()).row,
        'CellEditFixturesRow',
      );
      expect(
        TableNames.forTable('post_summary', const ClientSettings()).getter,
        'postSummary',
      );
    });

    test('a row override moves every name derived from it', () {
      const settings = ClientSettings(
        names: {'posts': ClientNameOverrides(row: 'BlogPostsRow')},
      );
      final names = TableNames.forTable('posts', settings);

      expect(names.row, 'BlogPostsRow');
      expect(names.id, 'BlogPostsId');
      expect(names.getter, 'blogPosts');
    });

    test('refuses a table name that cannot be a Dart identifier', () {
      expect(
        () => TableNames.forTable('2fa_tokens', const ClientSettings()),
        throwsA(
          isA<ClientNameException>()
              .having((e) => e.table, 'table', '2fa_tokens')
              .having((e) => e.message, 'message', contains('names:'))
              .having((e) => e.message, 'message', contains('row:')),
        ),
      );
    });

    test('refuses a table whose accessor would be a reserved word', () {
      expect(
        () => TableNames.forTable('class', const ClientSettings()),
        throwsA(
          isA<ClientNameException>().having(
            (e) => e.message,
            'message',
            contains('client.class'),
          ),
        ),
      );
    });

    test('the override is a real escape hatch for both', () {
      const settings = ClientSettings(
        names: {
          '2fa_tokens': ClientNameOverrides(row: 'TwoFactorTokensRow'),
          'class': ClientNameOverrides(row: 'SchoolClassRow'),
        },
      );

      expect(
        TableNames.forTable('2fa_tokens', settings).id,
        'TwoFactorTokensId',
      );
      expect(TableNames.forTable('class', settings).getter, 'schoolClass');
    });

    test('warns on two tables that resolve to the same names', () {
      // §10.4: the developer's call, but with a warning that names both
      // tables -- "duplicate class PostsRow" from the analyzer names neither.
      final names = ClientNameTable.forTables([
        'post_summary',
        'postSummary',
      ], const ClientSettings());

      expect(names.collisions, hasLength(1));
      final collision = names.collisions.single;
      expect(collision.base, 'PostSummary');
      expect(collision.message, contains('post_summary'));
      expect(collision.message, contains('postSummary'));
      expect(
        collision.message,
        contains('only sees one generation run'),
        reason:
            'the generator cannot see another project\'s output, and '
            'should not imply a guard it does not have',
      );
    });

    test('applies collision detection after overrides, not before', () {
      const settings = ClientSettings(
        names: {'postSummary': ClientNameOverrides(row: 'SummaryRow')},
      );

      final names = ClientNameTable.forTables([
        'post_summary',
        'postSummary',
      ], settings);

      expect(names.collisions, isEmpty);
    });
  });

  group('which tables are generated', () {
    const settings = ClientSettings(output: 'gen/zonai');

    test('framework-internal tables are left out by default', () {
      // Every `_`-prefixed table is one zonai owns. A generated `JwtApi` /
      // `RateLimitApi` would be discoverable, autocompleting, and -- since
      // types say nothing about permission -- would read as a supported API
      // over tables a consumer must never touch.
      expect(settings.includesTable('_jwt'), isFalse);
      expect(settings.includesTable('_rate_limit'), isFalse);
      expect(settings.includesTable('_photos'), isFalse);
      expect(settings.includesTable('posts'), isTrue);
    });

    test('tables.include opts one back in', () {
      const opted = ClientSettings(includeTables: ['_log']);

      expect(opted.includesTable('_log'), isTrue);
      expect(opted.includesTable('_jwt'), isFalse);
    });

    test('tables.exclude still wins over tables.include', () {
      const both = ClientSettings(
        excludeTables: ['_log'],
        includeTables: ['_log'],
      );

      expect(both.includesTable('_log'), isFalse);
    });

    test('excludedFrom names everything dropped, sorted', () {
      expect(settings.excludedFrom(['posts', '_jwt', '_abusers', 'authors']), [
        '_abusers',
        '_jwt',
      ]);
    });
  });
}
