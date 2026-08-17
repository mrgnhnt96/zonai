import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_playground/gen/zonai/zonai_client.g.dart';

/// The generated client, exercised against the rows the server actually
/// returns.
///
/// This file is also the compile check. `analysis_options.yaml` excludes
/// `**/lib/gen/**` from `dart analyze` -- reasonably, since it is generated --
/// so nothing else in the repo would notice if `zonai gen client` emitted Dart
/// that does not compile. Importing the barrel here makes the test runner
/// compile every generated library, and a syntax or type error becomes a
/// failure rather than silence.
void main() {
  group('PostsRow.fromJson', () {
    /// A row exactly as `/db/list` returns one: raw SQLite storage values,
    /// photo columns already resolved to URLs, `expanded` nested by
    /// foreign-key column name.
    Map<String, Object?> rawPost() => {
      'id': 'abc_ps',
      'photo': 'https://cdn.example.com/photos/pic_1.png',
      'author_id': 'abc_au',
      'title': 'Hello',
      'body': null,
      'created_at': 1764547200000,
      'updated_at': null,
      'expanded': {
        'author_id': {
          'id': 'abc_au',
          'name': 'Ada',
          'company_id': 'abc_co',
          'created_at': 1764547100000,
          'updated_at': null,
          'expanded': {
            'company_id': {
              'id': 'abc_co',
              'name': 'Zonai',
              'created_at': 1764547000000,
              'updated_at': null,
            },
          },
        },
      },
    };

    test('decodes raw storage values into Dart types', () {
      final post = PostsRow.fromJson(rawPost());

      expect(post.id, PostsId('abc_ps'));
      expect(post.title, 'Hello');
      expect(post.body, isNull);
      expect(post.photo, Uri.parse('https://cdn.example.com/photos/pic_1.png'));
      expect(
        post.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1764547200000),
      );
      expect(post.updatedAt, isNull);
    });

    test('types the foreign key by the table it points at', () {
      final post = PostsRow.fromJson(rawPost());

      // The static type is the point: an `AuthorsId` cannot be passed where a
      // `PostsId` belongs, which is the whole reason ids are minted per table.
      final AuthorsId author = post.authorId;
      expect(author, AuthorsId('abc_au'));
    });

    test('nests expanded relations recursively', () {
      final post = PostsRow.fromJson(rawPost());

      expect(post.expanded?.authorId?.name, 'Ada');
      expect(post.expanded?.authorId?.expanded?.companyId?.name, 'Zonai');
    });

    test('leaves expanded null when the response carried none', () {
      final row = rawPost()..remove('expanded');
      expect(PostsRow.fromJson(row).expanded, isNull);
    });

    test('ids erase to String, so they survive jsonEncode', () {
      final post = PostsRow.fromJson(rawPost());
      expect(jsonEncode({'id': post.id}), '{"id":"abc_ps"}');
    });
  });

  group('CellEditFixturesRow.fromJson', () {
    Map<String, Object?> rawFixture() => {
      'id': 'abc_ce',
      'label': 'a label',
      // `BooleanTransformer` stores 0/1.
      'flag': 1,
      'count': 7,
      'amount': 1.5,
      // `BigIntTransformer`: one sign byte, then big-endian magnitude.
      'big_count': [0, 1, 0],
      'happened_at': 1764547200000,
      'contact_email': 'ada@example.com',
      'status': 'published',
      // enumList / list / map are JSON-encoded strings on the wire.
      'tags': '["alpha","gamma"]',
      'keywords': '["dart","sqlite"]',
      'company_id': null,
      'meta': '{"theme":"dark"}',
      'payload': [1, 2, 3],
      'created_at': 1764547100000,
      'updated_at': null,
    };

    test('decodes every column kind the wire carries', () {
      final row = CellEditFixturesRow.fromJson(rawFixture());

      expect(row.flag, isTrue);
      expect(row.count, 7);
      expect(row.amount, 1.5);
      expect(row.bigCount, BigInt.from(256));
      expect(
        row.happenedAt,
        DateTime.fromMillisecondsSinceEpoch(1764547200000),
      );
      expect(row.status, 'published');
      expect(row.tags, ['alpha', 'gamma']);
      expect(row.keywords, ['dart', 'sqlite']);
      expect(row.meta, {'theme': 'dark'});
      expect(row.payload, [1, 2, 3]);
      expect(row.companyId, isNull);
    });

    test('a REAL column stored whole still decodes', () {
      final row = CellEditFixturesRow.fromJson(rawFixture()..['amount'] = 2);
      expect(row.amount, 2.0);
    });

    test('parses a row that never carries the secret column', () {
      // `secret_note` is stripped from every response by `_sanitizeRows`, so
      // the model does not declare it: a nullable field would be null in every
      // row that ever parses, and a non-nullable one would fail on all of them.
      // Absent is the honest model, and this row -- which has no `secret_note`
      // key at all, exactly as the server sends it -- has to parse.
      expect(rawFixture().containsKey('secret_note'), isFalse);
      expect(CellEditFixturesRow.fromJson(rawFixture()).label, 'a label');
    });
  });

  group('a view', () {
    test('parses like any other row', () {
      final row = PostSummaryRow.fromJson({
        'id': 'abc_ps',
        'title': 'Hello',
        'author_name': 'Ada',
      });

      expect(row.id, PostSummaryId('abc_ps'));
      expect(row.authorName, 'Ada');
    });
  });

  group('Authorization', () {
    test('bearer adds the prefix the server requires', () {
      // `_parseBearerAuthorization` returns null when the prefix is missing,
      // so a bare JWT proceeds as *unauthenticated* rather than failing. This
      // type is what makes that unrepresentable.
      expect(Authorization.bearer('jwt.abc').header, 'Bearer jwt.abc');
    });

    test('erases to String, so the wire is unchanged', () {
      const raw = Authorization.raw('Bearer jwt.abc');
      expect(raw.header, isA<String>());
      expect(identical(raw.header, raw.header), isTrue);
    });
  });
}
