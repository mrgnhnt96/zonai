import 'package:test/test.dart';
import 'package:zonai_playground/gen/zonai/tables/cell_edit_fixtures.g.dart';
import 'package:zonai_playground/gen/zonai/tables/posts.g.dart';
import 'package:zonai_playground/gen/zonai/tables/users.g.dart';
import 'package:zonai_playground/gen/zonai/zonai_runtime.g.dart';

/// Every column kind, fed the wrong runtime type.
///
/// §8.2 calls this the layer that actually protects a shipped app: it works
/// regardless of version skew and needs no server cooperation. What makes it
/// worth anything is the diagnosis, so that is what is asserted -- the
/// exception has to name the **table**, the **column**, the expected **kind**
/// and the **actual runtime type**, every time.
///
/// A `TypeError` escaping any decode path is the failure this file exists to
/// catch. `type 'String' is not a subtype of type 'int'`, thrown from inside a
/// generated `fromJson`, names none of the four.
void main() {
  /// One wrong-type case: the column, the kind the schema says it is, and a
  /// value of a type that kind never arrives as.
  void expectsKind(
    String description, {
    required String table,
    required String column,
    required String kind,
    required Object? wrong,
    required void Function(Map<String, Object?>) parse,
    required Map<String, Object?> Function() row,
  }) {
    test('$table.$column ($description)', () {
      final bad = row()..[column] = wrong;

      Object? thrown;
      try {
        parse(bad);
      } catch (error) {
        thrown = error;
      }

      expect(
        thrown,
        isA<ZonaiRowParseException>(),
        reason: 'a TypeError here would name none of the four things',
      );

      final failure = thrown! as ZonaiRowParseException;
      expect(failure.table, table);
      expect(failure.column, column);
      expect(failure.expected, contains(kind));
      expect(failure.actual, wrong.runtimeType);

      // The message a developer actually sees carries all four.
      expect(failure.toString(), contains(table));
      expect(failure.toString(), contains(column));
      expect(failure.toString(), contains(kind));
      expect(failure.toString(), contains('${wrong.runtimeType}'));
    });
  }

  Map<String, Object?> fixtureRow() => {
    'id': 'abc_ce',
    'label': 'a label',
    'flag': 1,
    'count': 7,
    'amount': 1.5,
    'big_count': [0, 1],
    'happened_at': 1764547200000,
    'contact_email': 'ada@example.com',
    'status': 'published',
    'tags': '["alpha"]',
    'keywords': '["dart"]',
    'company_id': null,
    'meta': '{"theme":"dark"}',
    'payload': [1, 2, 3],
    'created_at': 1764547100000,
    'updated_at': null,
  };

  Map<String, Object?> postRow() => {
    'id': 'abc_ps',
    'photo': 'https://cdn.example.com/photos/pic_1.png',
    'author_id': 'abc_au',
    'title': 'Hello',
    'body': null,
    'created_at': 1764547200000,
    'updated_at': null,
  };

  Map<String, Object?> userRow() => {
    'id': 'abc_us',
    'name': 'Ada',
    'email': 'ada@example.com',
    'is_verified': 1,
    'created_at': 1764547200000,
    'updated_at': null,
  };

  group('every §4.1 kind, given the wrong runtime type', () {
    void fixture(
      String description, {
      required String column,
      required String kind,
      required Object? wrong,
    }) {
      expectsKind(
        description,
        table: 'cell_edit_fixtures',
        column: column,
        kind: kind,
        wrong: wrong,
        parse: CellEditFixturesRow.fromJson,
        row: fixtureRow,
      );
    }

    fixture(
      'an int where the id String belongs',
      column: 'id',
      kind: 'id',
      wrong: 7,
    );
    fixture(
      'an int where text belongs',
      column: 'label',
      kind: 'text',
      wrong: 7,
    );
    fixture(
      'a String where the 0/1 int belongs',
      column: 'flag',
      kind: 'boolean',
      wrong: 'true',
    );
    fixture(
      'a String where an integer belongs',
      column: 'count',
      kind: 'integer',
      wrong: '7',
    );
    fixture(
      'a String where a real belongs',
      column: 'amount',
      kind: 'real',
      wrong: '1.5',
    );
    fixture(
      'a String where the bigInt blob belongs',
      column: 'big_count',
      kind: 'bigInt',
      wrong: 'ten',
    );
    fixture(
      'an ISO string where epoch ms belongs',
      column: 'happened_at',
      kind: 'dateTime',
      wrong: '2026-08-17T00:00:00Z',
    );
    fixture(
      'an int where an email belongs',
      column: 'contact_email',
      kind: 'email',
      wrong: 1,
    );
    fixture(
      'an int where the enum name belongs',
      column: 'status',
      kind: 'enum',
      wrong: 3,
    );
    fixture(
      'a bare int where the JSON-encoded enum list belongs',
      column: 'tags',
      kind: 'enumList',
      wrong: 3,
    );
    fixture(
      'a bare int where the JSON-encoded list belongs',
      column: 'keywords',
      kind: 'list',
      wrong: 3,
    );
    fixture(
      'a bare int where the JSON-encoded object belongs',
      column: 'meta',
      kind: 'map',
      wrong: 3,
    );
    fixture(
      'a String where the blob byte list belongs',
      column: 'payload',
      kind: 'blob',
      wrong: 'AQID',
    );
    fixture(
      'a String where createdAt epoch ms belongs',
      column: 'created_at',
      kind: 'createdAt',
      wrong: '2026-08-17',
    );
    fixture(
      'a String where updatedAt epoch ms belongs',
      column: 'updated_at',
      kind: 'updatedAt',
      wrong: '2026-08-17',
    );

    expectsKind(
      'an int where the resolved photo URL belongs',
      table: 'posts',
      column: 'photo',
      kind: 'photo',
      wrong: 12,
      parse: PostsRow.fromJson,
      row: postRow,
    );

    expectsKind(
      'a String where the 0/1 isVerified int belongs',
      table: 'users',
      column: 'is_verified',
      kind: 'isVerified',
      wrong: 'yes',
      parse: UsersRow.fromJson,
      row: userRow,
    );
  });

  group('kinds no playground column has', () {
    // `photos` and `deviceToken` are in the shape vocabulary but not in any of
    // the playground's tables, so they are covered against the shared reader
    // directly rather than left untested.
    const reader = ZonaiRowReader('gallery');

    test('photos', () {
      expect(
        () => reader.uriList({'shots': 12}, 'shots', kind: 'photos'),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.table, 'table', 'gallery')
              .having((e) => e.column, 'column', 'shots')
              .having((e) => e.expected, 'expected', contains('photos'))
              .having((e) => e.actual, 'actual', int),
        ),
      );
    });

    test('deviceToken', () {
      expect(
        () => reader.string({'token': 12}, 'token', kind: 'deviceToken'),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.expected, 'expected', contains('deviceToken'))
              .having((e) => e.actual, 'actual', int),
        ),
      );
    });
  });

  group('a column that is not there', () {
    test('reports Null as the actual type', () {
      final row = postRow()..remove('title');

      expect(
        () => PostsRow.fromJson(row),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.table, 'table', 'posts')
              .having((e) => e.column, 'column', 'title')
              .having((e) => e.expected, 'expected', contains('text'))
              .having((e) => e.actual, 'actual', Null),
        ),
      );
    });

    test('a nullable column simply stays null', () {
      expect(PostsRow.fromJson(postRow()..remove('body')).body, isNull);
    });
  });

  group('a JSON column whose payload decodes to the wrong shape', () {
    // The column really is a `String` on the wire here, so the useful thing to
    // report is what it decoded *to* -- "you gave me an object where a list
    // belongs" -- rather than the `String` that was technically handed over.
    test('names the decoded type, not String', () {
      expect(
        () => CellEditFixturesRow.fromJson(
          fixtureRow()..['keywords'] = '{"not":"a list"}',
        ),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.column, 'column', 'keywords')
              .having((e) => e.expected, 'expected', contains('list'))
              .having((e) => e.actual, 'actual', isNot(String)),
        ),
      );
    });

    test('the same, the other way round', () {
      expect(
        () => CellEditFixturesRow.fromJson(
          fixtureRow()..['meta'] = '["not","an object"]',
        ),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.column, 'column', 'meta')
              .having((e) => e.expected, 'expected', contains('map'))
              .having((e) => e.actual, 'actual', isNot(String)),
        ),
      );
    });
  });

  group('malformed JSON in a text column', () {
    test('reports as drift rather than a bare FormatException', () {
      expect(
        () => CellEditFixturesRow.fromJson(fixtureRow()..['meta'] = '{oops'),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.column, 'column', 'meta')
              .having((e) => e.expected, 'expected', contains('map')),
        ),
      );
    });
  });

  group('an expanded relation with a bad row', () {
    test('names the related table, not the outer one', () {
      final row = postRow()
        ..['expanded'] = {
          'author_id': {'id': 'abc_au', 'name': 7, 'created_at': 1},
        };

      expect(
        () => PostsRow.fromJson(row),
        throwsA(
          isA<ZonaiRowParseException>()
              .having((e) => e.table, 'table', 'authors')
              .having((e) => e.column, 'column', 'name')
              .having((e) => e.actual, 'actual', int),
        ),
      );
    });
  });
}
