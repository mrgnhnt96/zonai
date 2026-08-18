// The one import is the point of this file -- do not add another.
import 'package:test/test.dart';
import 'package:zonai_playground/gen/zonai/zonai_client.g.dart';

/// The consumer's-eye view: everything a generated signature hands back has to
/// be nameable from the generated barrel alone.
///
/// This file imports exactly one library and no `package:zonai_client` at all.
/// That is the whole test -- a Dart `export` of a table file carries what that
/// file *declares*, never what it imports, so before the barrel re-exported
/// `zonai_client` this did not compile. It failed on `Paginated`, which is the
/// declared return type of every generated `list()`: a consumer could call the
/// method but could not write down what it gave them.
///
/// The assertions below are almost beside the point. If the re-export is
/// dropped or a `hide` clause grows a name it should not have, this file stops
/// compiling and the failure lands here, naming the type -- rather than in
/// somebody's app.
void main() {
  group('the barrel alone is enough to name', () {
    test('Paginated, which every list() returns', () {
      const Paginated<PostsRow> empty = Paginated<PostsRow>(
        items: [],
        total: 0,
      );

      expect(empty.items, isEmpty);
      expect(empty.total, 0);
    });

    test('the Where vocabulary a filter is built from', () {
      final Where filter = And([
        Posts.title.contains('draft'),
        Posts.createdAt.gt(DateTime.utc(2026)),
      ]);

      expect(filter, isA<Where>());
    });

    test('OrderByTerm and SortDirection, which a token hands back', () {
      final OrderByTerm term = Posts.createdAt.desc;

      expect(term.column, 'created_at');
      expect(term.direction, SortDirection.desc);
    });

    test('ListBody, the untyped call the typed one delegates to', () {
      const ListBody body = ListBody(table: 'posts');

      expect(body.table, 'posts');
    });

    test('the update vocabulary a Patch renders into', () {
      final List<Update> updates = PostsUpdate(
        title: Field.set('renamed'),
      ).toUpdates();

      expect(updates.single, isA<ColumnUpdate>());
    });
  });
}
