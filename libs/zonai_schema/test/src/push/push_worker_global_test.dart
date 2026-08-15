import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The worker half of `push`, which nothing else exercises.
///
/// The engine tests drive `ZonaiDb.enqueuePush` directly — the host side.
/// Everything between an app author writing `await push(...)` and that method
/// being called is IPC: a scoped global bound inside `runWithParent`, a
/// request written to stdout, a response matched back by id. A break anywhere
/// in there fails in every real server and in none of the other tests.
class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  /// Feeds a host reply back in, the way the real stdin loop would.
  void reply(Map<String, dynamic> message) => _incoming.add(message);

  @override
  void dispose() => _incoming.close();
}

Future<(MessageHandler<CronRequest>, _FakeMessageIo)> _worker() async {
  final io = _FakeMessageIo();
  final handler = MessageHandler<CronRequest>(
    fromUnknownRequest: CronRequest.fromRequest,
    onMessage: (request) async => null,
    io: io,
  );
  unawaited(handler.listen());
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return (handler, io);
}

/// The `EnqueuePushRequest` the worker wrote, waiting for it to appear.
Future<Map<String, dynamic>> _awaitEnqueue(_FakeMessageIo io) async {
  for (var i = 0; i < 50; i++) {
    for (final message in io.sent) {
      if (message['path'] == 'request/.enqueue_push') return message;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('the worker never wrote an enqueue_push request');
}

/// Answers the outstanding enqueue so the worker's pending future resolves.
///
/// Without it, `io.dispose()` completes it with an error nobody awaited, and
/// the test fails on an unhandled async exception that has nothing to do with
/// what it was asserting.
void _settle(_FakeMessageIo io, Map<String, dynamic> sent) {
  io.reply(
    EnqueuePushResponse(
      id: sent['id'] as String,
      jobId: PushJobId.generate().value,
    ).toJson(),
  );
}

void main() {
  const message = PushMessage(
    title: 'New reply',
    body: 'Someone replied',
    collapseKey: 'post:1',
    data: {'postId': '1'},
  );

  test('push is unavailable outside a request scope, and says so', () async {
    // A bare `read` on an unbound ref would throw something opaque about
    // providers. An author calling `push` from the wrong place deserves to be
    // told which place is right.
    await expectLater(
      () => push(message, table: 't', column: 'c'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('extension hook'), contains('cron')),
        ),
      ),
    );
  });

  test('inside runWithParent, push writes an EnqueuePushRequest', () async {
    final (handler, io) = await _worker();
    final parent = RunCronJobRequest(name: '_notify');

    unawaited(
      handler.runWithParent(parent, () async {
        await push(
          message,
          table: 'device_tokens',
          column: 'token',
          where: const In('user_id', ['u1', 'u2']),
        );
      }),
    );

    final sent = await _awaitEnqueue(io);
    final decoded = Request.fromJson(sent) as EnqueuePushRequest;

    expect(decoded.table, 'device_tokens');
    expect(decoded.column, 'token');
    expect(decoded.message, message);
    expect(decoded.where, isA<In>());

    _settle(io, sent);
    io.dispose();
  });

  test('the ambient identity travels with the request', () async {
    final (handler, io) = await _worker();

    // The host refuses a non-admin enqueue. A cron's identity being dropped
    // on the way out would turn every scheduled notification into a 403 —
    // and it would only ever show up at runtime.
    unawaited(
      handler.runWithParent(
        RunCronJobRequest(name: '_notify'),
        () async => push(message, table: 't', column: 'c'),
      ),
    );

    final sent = await _awaitEnqueue(io);
    expect(sent['jwt'], isNotNull);
    expect(
      Jwt.maybeFromJson(sent['jwt'])?.admin.isAdmin,
      isTrue,
      reason: 'a cron firing carries CronJwt, and the host gates on it',
    );

    _settle(io, sent);
    io.dispose();
  });

  test('the job id from the host is what push returns', () async {
    final (handler, io) = await _worker();
    final id = PushJobId.generate();

    PushJobId? returned;
    unawaited(
      handler.runWithParent(RunCronJobRequest(name: '_notify'), () async {
        returned = await push(message, table: 't', column: 'c');
      }),
    );

    final sent = await _awaitEnqueue(io);
    io.reply(
      EnqueuePushResponse(id: sent['id'] as String, jobId: id.value).toJson(),
    );

    for (var i = 0; i < 50 && returned == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(returned, id);
    io.dispose();
  });

  test('a null job id becomes a StateError naming AppConfig.push', () async {
    final (handler, io) = await _worker();

    Object? thrown;
    unawaited(
      handler.runWithParent(RunCronJobRequest(name: '_notify'), () async {
        try {
          await push(message, table: 't', column: 'c');
        } catch (e) {
          thrown = e;
        }
      }),
    );

    final sent = await _awaitEnqueue(io);
    // Null is how the host reports "no push config" — it logs a warning and
    // enqueues nothing rather than throwing, because a missing config must be
    // loud and not fatal on the host. The worker turns it into a throw at the
    // call site, which is where the stack still points at the code that asked
    // to send.
    io.reply(
      EnqueuePushResponse(id: sent['id'] as String, jobId: null).toJson(),
    );

    for (var i = 0; i < 50 && thrown == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(thrown, isA<StateError>());
    expect('$thrown', contains('AppConfig.push'));
    io.dispose();
  });

  test('push is awaited, not queued as a side effect', () async {
    final (handler, io) = await _worker();

    // `mutate.*` is parked against the parent's id and replayed later, so its
    // caller learns nothing. `push` cannot work that way: it has to hand back
    // the id of the row the host just wrote. If it were ever converted to a
    // queued side effect, `runWithParent` would return without a reply having
    // been needed — and this would hang rather than pass.
    var completed = false;
    final body = handler.runWithParent(
      RunCronJobRequest(name: '_notify'),
      () async {
        await push(message, table: 't', column: 'c');
        completed = true;
      },
    );

    final sent = await _awaitEnqueue(io);
    expect(
      completed,
      isFalse,
      reason: 'push must still be waiting for the host to answer',
    );

    io.reply(
      EnqueuePushResponse(
        id: sent['id'] as String,
        jobId: PushJobId.generate().value,
      ).toJson(),
    );
    await body;

    expect(completed, isTrue);
    io.dispose();
  });

  test('a nested scope binds its own push, not the outer one', () async {
    // The same trap `scheduled_cron_mutations_test` documents for `mutate`:
    // a scheduled cron nests inside the scope that started the scheduler, and
    // a timer fires in the zone that created it. `_pushProvider` is in
    // `override`, not `includeIfAbsent`, so the inner request wins — this is
    // what stops a firing hours later carrying the boot request's identity.
    final (handler, io) = await _worker();

    final start = StartCronsRequest();
    final run = RunCronJobRequest(name: '_notify');

    unawaited(
      handler.runWithParent(start, () async {
        await handler.runWithParent(run, () async {
          await push(message, table: 't', column: 'c');
        });
      }),
    );

    final sent = await _awaitEnqueue(io);
    expect(
      Jwt.maybeFromJson(sent['jwt'])?.admin.isAdmin,
      isTrue,
      reason: 'the inner cron identity, not whatever started the scheduler',
    );

    _settle(io, sent);
    io.dispose();
  });
}
