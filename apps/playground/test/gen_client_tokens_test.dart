import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';
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

  group('a typed expand path sends exactly what the string form sent', () {
    test('one hop, and a chained hop, produce the dotted wire form', () {
      expect(Posts.expand.authorId.path, 'author_id');
      expect(Posts.expand.authorId.companyId.path, 'author_id.company_id');
    });

    test('the request body is byte-identical to the hand-written strings', () {
      // The whole promise of this change is that nothing on the wire moves.
      // Asserting the two payloads rather than reading the serializer is the
      // only way to know it.
      String encode(List<String> expand) =>
          jsonEncode(ListBody(table: 'posts', expand: expand).toJson());

      final typed = encode([
        for (final e in [
          Posts.expand.authorId,
          Posts.expand.authorId.companyId,
        ])
          e.path,
      ]);
      final byHand = encode(const ['author_id', 'author_id.company_id']);

      expect(typed, byHand);
    });

    test('a self-reference is chainable, and the root is const', () {
      // `Posts.expand` is a `static const`, which is why the depth assert
      // cannot live in the constructor -- `List.length` is not const-evaluable.
      const root = Posts.expand;
      expect(root.segments, isEmpty);
      expect(root.path, '');
    });

    test('a table with nothing to expand still has the type', () {
      // Companies is the target of authors.company_id and has no keys of its
      // own; without its own Expand type, AuthorsExpand.companyId has nothing
      // to return and the generated output does not compile.
      expect(Companies.expand, isA<ExpandPath>());
      expect(Companies.expand.segments, isEmpty);
    });
  });

  group('the write surface says what a nullable field could not', () {
    test('"leave alone" and "set to NULL" are different payloads', () {
      // This is the entire reason each field takes a `Patch` instead of a raw
      // value. `PostsUpdate({String? body})` cannot express the second one at
      // all, and `Literal(null)` is a real operation the server applies.
      final leaveAlone = const PostsUpdate().toUpdates();
      final setToNull = const PostsUpdate(body: Field.clear()).toUpdates();
      final setToValue = PostsUpdate(body: Field.set('hi')).toUpdates();

      expect(leaveAlone, isEmpty);
      expect(
        jsonEncode([for (final u in setToNull) u.toJson()]),
        isNot(jsonEncode([for (final u in leaveAlone) u.toJson()])),
      );
      expect(setToNull.single.toJson(), {
        'type': 'column',
        'column': 'body',
        'value': {'type': 'literal', 'value': null},
      });
      expect((setToValue.single.toJson()['value'] as Map)['value'], 'hi');
    });

    test('a DateTime survives the write path as epoch milliseconds', () {
      // Measured: a raw DateTime reaches jsonEncode and throws
      // JsonUnsupportedObjectError, in a create body and inside a Literal
      // alike. The filter path normalizes and the write path does not, so the
      // generated client has to.
      final at = DateTime.utc(2025, 6, 1);

      // Not `updated_at`: that column is server-managed and correctly has no
      // write field at all. `happened_at` is an ordinary writable dateTime.
      final update = CellEditFixturesUpdate(
        happenedAt: Field.set(at),
      ).toUpdates();
      expect(
        (update.single.toJson()['value'] as Map)['value'],
        at.millisecondsSinceEpoch,
      );

      final create = CellEditFixturesCreate(
        label: 'x',
        flag: true,
        count: 1,
        amount: 1.5,
        happenedAt: at,
        contactEmail: 'a@b.c',
        status: CellEditFixturesStatus.draft,
        tags: const [CellEditFixturesTags.alpha],
        keywords: const [],
        secretNote: 's',
        meta: const {},
      ).toObject();
      expect(create['happened_at'], at.millisecondsSinceEpoch);
      expect(() => jsonEncode(create), returnsNormally);
    });

    test('the vocabulary is gated by column kind', () {
      // `increment` exists on a number and nowhere else; `addAll` on a list.
      expect(
        const CellEditFixturesUpdate(
          count: NumField.increment(),
        ).toUpdates().single.toJson()['value'],
        {'type': 'increment'},
      );
      expect(
        CellEditFixturesUpdate(
          tags: ListField.addAll(const [CellEditFixturesTags.beta]),
        ).toUpdates().single.toJson()['value'],
        {
          'type': 'add_all',
          'values': ['beta'],
        },
      );
    });

    test('create omits what it was not given, and keeps what it was', () {
      final withId = PostsCreate(
        id: const PostsId('abc_ps'),
        authorId: const AuthorsId('abc_au'),
        title: 'Hello',
      ).toObject();
      final withoutId = PostsCreate(
        authorId: const AuthorsId('abc_au'),
        title: 'Hello',
      ).toObject();

      expect(withId['id'], 'abc_ps', reason: 'an id erases to its String');
      expect(
        withoutId.containsKey('id'),
        isFalse,
        reason: 'the server generates one when absent',
      );
      expect(withoutId['author_id'], 'abc_au');
    });
  });

  group('enum columns are typed without becoming brittle', () {
    test('named constants, and the wire carries the member name', () {
      expect(CellEditFixturesStatus.draft.value, 'draft');
      expect(CellEditFixturesStatus.values.map((e) => e.value), [
        'draft',
        'published',
        'archived',
      ]);
      expect(
        CellEditFixtures.status.eq(CellEditFixturesStatus.published).toJson(),
        {'type': 'eq', 'column': 'status', 'value': 'published'},
      );
    });

    test('a member the server adds later still arrives intact', () {
      // The whole reason this is an extension type and not a Dart `enum`. A
      // real enum has to either throw here or collapse the value to a
      // sentinel; this keeps it, and says it was not declared.
      const added = CellEditFixturesStatus('rescinded');

      expect(added.isKnown, isFalse);
      expect(added.value, 'rescinded', reason: 'nothing is lost');
      expect(CellEditFixturesStatus.draft.isKnown, isTrue);
    });

    test('a row parses an unknown member rather than failing', () {
      final row = CellEditFixturesRow.fromJson({
        'id': 'abc_cf',
        'label': 'x',
        'flag': 1,
        'count': 1,
        'amount': 1.5,
        'big_count': [0, 1],
        'happened_at': 1764547200000,
        'contact_email': 'a@b.c',
        'status': 'rescinded',
        'tags': '["alpha","zeta"]',
        'keywords': '[]',
        'company_id': null,
        'meta': '{}',
        'payload': null,
        'created_at': 1764547200000,
        'updated_at': null,
      });

      expect(row.status, const CellEditFixturesStatus('rescinded'));
      expect(row.status.isKnown, isFalse);
      expect(row.tags, [
        CellEditFixturesTags.alpha,
        const CellEditFixturesTags('zeta'),
      ]);
      expect(row.tags.last.isKnown, isFalse);
    });

    test('it erases on the write path, in both directions', () {
      expect(
        CellEditFixturesUpdate(
          status: Field.set(CellEditFixturesStatus.archived),
        ).toUpdates().single.toJson()['value'],
        {'type': 'literal', 'value': 'archived'},
      );
      expect(
        CellEditFixturesUpdate(
          tags: ListField.add(CellEditFixturesTags.beta),
        ).toUpdates().single.toJson()['value'],
        {'type': 'add', 'value': 'beta'},
      );
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
      expect(
        CellEditFixtures.status
            .eq(CellEditFixturesStatus.draft)
            .toJson()['column'],
        'status',
      );
      expect(CellEditFixtures.flag.eq(true).toJson()['value'], true);
      expect(CellEditFixtures.count.gt(3).toJson()['value'], 3);
      expect(CellEditFixtures.companyId.isNull.toJson(), {
        'type': 'is_null',
        'column': 'company_id',
      });
    });
  });
}
