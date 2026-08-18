import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_playground/gen/zonai/zonai_client.g.dart';

/// The typed `listen` mirror, exercised against a fake data source.
///
/// Cancellation is asserted rather than assumed on purpose. Two confirmed leaks
/// have already been found in this project's streaming path -- revali's
/// `asBroadcastStream` `onCancel`, and a SQL dependency-parser quote bug -- and
/// a typed mirror that subscribed differently from the untyped one could
/// reopen either. The generated code delegates to `DbListen` and adds only a
/// `.map`, and this is what proves the delegation does not swallow a cancel.
void main() {
  late _FakeDb fake;
  late Db db;

  setUp(() {
    fake = _FakeDb();
    db = Db(db: fake);
  });

  test('one() decodes rows off the stream', () async {
    fake.oneController.add({
      'id': 'abc_ps',
      'photo': null,
      'author_id': 'abc_au',
      'title': 'Hello',
      'body': null,
      'created_at': 1764547200000,
      'updated_at': null,
    });
    // Not awaited: `close()` on a controller nobody has listened to yet does
    // not complete until the stream is drained, which is a deadlock here.
    unawaited(fake.oneController.close());

    final rows = await PostsListen(
      db,
    ).one(where: Posts.id.eq(const PostsId('abc_ps'))).toList();

    expect(rows, hasLength(1));
    expect(rows.single.title, 'Hello');
    expect(rows.single.id, const PostsId('abc_ps'));
  });

  test('count() passes the typed where straight through', () async {
    fake.countController.add(3);
    unawaited(fake.countController.close());

    final counts = await PostsListen(
      db,
    ).count(where: Posts.title.eq('Hello')).toList();

    expect(counts, [3]);
    expect(fake.lastCountBody!.table, 'posts');
    expect(fake.lastCountBody!.where.toJson(), {
      'type': 'eq',
      'column': 'title',
      'value': 'Hello',
    });
  });

  test(
    'list() serializes typed expand paths to the dotted wire form',
    () async {
      unawaited(fake.listController.close());

      await PostsListen(
        db,
      ).list(expand: [Posts.expand.authorId.companyId]).toList();

      expect(fake.lastListBody!.expand, ['author_id.company_id']);
    },
  );

  test('cancelling a generated stream cancels the underlying one', () async {
    // The whole point. A `.map` over a stream that ignores cancel is exactly
    // how a subscription outlives the widget that opened it.
    final sub = PostsListen(
      db,
    ).one(where: Posts.id.eq(const PostsId('abc_ps'))).listen((_) {});

    await pumpEventQueue();
    expect(
      fake.oneController.hasListener,
      isTrue,
      reason: 'the subscription reached the data source',
    );

    await sub.cancel();
    await pumpEventQueue();

    expect(
      fake.oneCancelled,
      isTrue,
      reason: 'cancel must propagate, or the subscription leaks',
    );
  });
}

/// Implements only the three stream methods; everything else throws rather
/// than silently returning null, so a test that drifts onto an unfaked path
/// fails loudly.
class _FakeDb implements DbDataSource {
  final oneController = StreamController<Map<String, Object?>>();
  final listController = StreamController<List<Map<String, Object?>>>();
  final countController = StreamController<int>();

  bool oneCancelled = false;
  StreamListBody? lastListBody;
  StreamCountBody? lastCountBody;

  _FakeDb() {
    oneController.onCancel = () => oneCancelled = true;
  }

  @override
  Stream<Map<String, Object?>> streamOne({
    required StreamBody body,
    String? authorization,
  }) => oneController.stream;

  @override
  Stream<List<Map<String, Object?>>> streamList({
    required StreamListBody body,
    String? authorization,
  }) {
    lastListBody = body;
    return listController.stream;
  }

  @override
  Stream<int> streamCount({
    required StreamCountBody body,
    String? authorization,
  }) {
    lastCountBody = body;
    return countController.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
