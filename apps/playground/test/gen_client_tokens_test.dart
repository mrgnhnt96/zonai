import 'package:test/test.dart';
import 'package:zonai_playground/gen/zonai/zonai_client.g.dart';

/// The §5.4 column tokens, exercised down to the wire form.
///
/// A token's whole promise is *if it compiles, it works*, and only half of
/// that is checkable by looking at the emitted source. These assertions are
/// the other half: that `Posts.createdAt.gt(aDateTime)` really does put epoch
/// milliseconds on the wire, and that an extension-type id really does erase
/// to a bare string. Both are load-bearing and neither is visible in a golden.
///
/// Importing the barrel also compiles every generated library, so this file is
/// a compile check for the tokens the same way `gen_client_test.dart` is one
/// for the row models.
void main() {
  group('a token builds the Where the untyped client already takes', () {
    test('eq on a text column', () {
      expect(Posts.title.eq('Hello').toJson(), {
        'type': 'eq',
        'column': 'title',
        'value': 'Hello',
      });
    });

    test('an id erases to a bare string, needing no custom encoder', () {
      // §4.5: extension types over String erase at runtime, so `PostsId`
      // survives jsonEncode untouched.
      expect(Posts.id.eq(const PostsId('abc_ps')).toJson(), {
        'type': 'eq',
        'column': 'id',
        'value': 'abc_ps',
      });
    });

    test('a foreign key is typed by the table it points at', () {
      // Passing a PostsId here would not compile -- that is the point.
      expect(Posts.authorId.eq(const AuthorsId('abc_au')).toJson(), {
        'type': 'eq',
        'column': 'author_id',
        'value': 'abc_au',
      });
    });

    test('a DateTime normalizes to epoch milliseconds', () {
      final at = DateTime.utc(2025, 12, 1);
      expect(Posts.createdAt.gt(at).toJson(), {
        'type': 'gt',
        'column': 'created_at',
        'value': at.millisecondsSinceEpoch,
      });
    });

    test('inList carries every value through the same normalization', () {
      expect(
        Posts.id.inList(const [PostsId('a'), PostsId('b')]).toJson()['values'],
        ['a', 'b'],
      );
    });

    test('isNull goes through the Where.isNull factory', () {
      // `zonai_client` deliberately does not export `Null`; it would shadow
      // `dart:core`'s. The token has to build the clause without naming it.
      expect(Posts.body.isNull.toJson(), {'type': 'is_null', 'column': 'body'});
      expect(Posts.updatedAt.isNotNull.toJson(), {
        'type': 'not_null',
        'column': 'updated_at',
      });
    });

    test('string matching, including the operator the sketch omitted', () {
      expect(Users.email.startsWith('a').toJson()['type'], 'starts_with');
      expect(Users.email.endsWith('z').toJson()['type'], 'ends_with');
      expect(Users.name.contains('or').toJson()['type'], 'contains');
      expect(Users.name.notContains('or').toJson()['type'], 'not_contains');
    });

    test('ordering uses the named-argument OrderByTerm', () {
      // OrderByTerm takes {required column, direction} -- a doc page once
      // shipped it positional, which is why this is asserted rather than
      // assumed.
      expect(Posts.createdAt.desc.toJson(), {
        'column': 'created_at',
        'direction': 'desc',
      });
      expect(Posts.createdAt.asc.toJson(), {'column': 'created_at'});
    });
  });

  group('what a token deliberately cannot do', () {
    test('a nullable column keeps the full comparable surface', () {
      // The reason NullableColumnRef<T> is a subclass and not ColumnRef<T?>:
      // `DateTime?` is not Comparable, so the sketch's shape would have lost
      // gt/lt on exactly the nullable timestamps people filter on.
      final at = DateTime.utc(2025);
      expect(Posts.updatedAt.gt(at).toJson()['column'], 'updated_at');
      expect(Posts.updatedAt.lte(at).toJson()['type'], 'lte');
    });

    test('no token exists for a secret, a photo, or a JSON-encoded column', () {
      // Compile-time *absence* cannot be observed from inside Dart, so this
      // asserts the positive half instead: the tokens that must exist do, and
      // each one carries the type that makes its operator set correct. The
      // absent ones are pinned by the emitter tests, which can see the source.
      //
      // users.password is secret; posts.photo stores an id but reads back a
      // URL; cell_edit_fixtures carries bigInt/enumList/list/map/blob columns.
      expect(CellEditFixtures.label.eq('x').toJson()['column'], 'label');
      expect(CellEditFixtures.status.eq('draft').toJson()['column'], 'status');
      expect(CellEditFixtures.flag.eq(true).toJson()['value'], true);
      expect(CellEditFixtures.count.gt(3).toJson()['value'], 3);
      expect(CellEditFixtures.companyId.isNull.toJson(), {
        'type': 'is_null',
        'column': 'company_id',
      });
    });
  });
}
