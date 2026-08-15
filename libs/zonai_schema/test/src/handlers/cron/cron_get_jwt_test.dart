import 'dart:async';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/types/cron_jwt.dart';
import 'package:zonai_schema/src/types/where.dart';

// Reported by two independent consumers building against zonai (crawler-m8 and
// crawler-m9a, the second reading it fresh), 2026-08-14: an anti-spam fan-out
// cron failed on EVERY tick since it landed -- `Access denied: action list on
// table loss_events` -- while `dart analyze`, 199 headless tests, `zonai
// compile` and a burst test were all green over a feature that did nothing.
//
// The cause was an asymmetry between two halves of one API. `mutate` and
// `email` are built per request, inside `runWithParent`, so they close over
// `request.jwt`. `get` is built once for the whole listen loop, before any
// request exists, so it had only the caller's explicit argument -- and a cron
// job body passes none. A cron that WRITES therefore ran as `CronJwt` and
// worked; a cron that READS ran as nobody and was denied.
//
// That combination is close to the least guessable one available, and
// `docs/cron.md` described the opposite ("Reads (`get`) run immediately and
// respect collection/row rules for `CronJwt`"), so a consumer following the
// docs wrote the failing version with no reason to suspect it.
//
// EVERY TEST HERE DRIVES THE REAL TRANSPORT -- a request pushed into `incoming`
// and handled by the worker's own listen loop -- rather than calling
// `runWithParent` directly. That is not ceremony: `get` resolves from a ref
// bound inside `listen()`, so it is unreachable from a test that skips it, and
// a suite that reached past the loop would be testing a different program.
//
// WHAT THIS FILE PROVES, AND WHAT IT DOES NOT: these are wire-level assertions
// -- that a read leaving a cron firing carries the cron identity. They do not
// exercise a rules worker denying a real table, so they cannot prove the
// end-to-end denial is gone; they pin the mechanism that caused it. The
// end-to-end case belongs against a bound server, which is where both
// consumers said this whole class of defect only ever becomes visible.
class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  void push(Map<String, dynamic> message) => _incoming.add(message);

  @override
  void dispose() => _incoming.close();
}

/// Feeds [incoming] through a real listen loop and runs [body] as the handler
/// for it, then returns everything the worker put on the wire.
///
/// Nothing ever answers a `get` here -- the host is what answers it -- so every
/// read below is fire-and-forget and asserted on the wire instead. That is also
/// the only place the JWT is observable: it is chosen when the request is
/// built, not when the response comes back.
Future<_FakeMessageIo> _handle<R extends Request>(
  Map<String, dynamic> incoming,
  R Function(UnknownRequest) fromUnknownRequest,
  Future<void> Function() body,
) async {
  final io = _FakeMessageIo();
  final handled = Completer<void>();

  final handler = MessageHandler<R>(
    fromUnknownRequest: fromUnknownRequest,
    onMessage: (request) async {
      await body();
      handled.complete();
      return null;
    },
    io: io,
  );

  unawaited(handler.listen());
  await Future<void>.delayed(const Duration(milliseconds: 10));

  io.push(incoming);
  await handled.future;
  await Future<void>.delayed(const Duration(milliseconds: 10));

  addTearDown(io.dispose);
  return io;
}

Map<String, dynamic> _onlyGet(_FakeMessageIo io) {
  final gets = io.sent
      .where((m) => '${m['path']}'.endsWith('.get_record'))
      .toList();
  expect(gets, hasLength(1), reason: 'the read must reach the wire at all');
  return gets.single;
}

void main() {
  test('a read issued inside a cron firing carries the cron identity, the way '
      'a write from the same scope always has', () async {
    final io = await _handle(
      RunCronJobRequest(name: '_anti_spam_fan_out').toJson(),
      CronRequest.fromRequest,
      () async {
        // No `jwt:` argument on either -- exactly what a cron job body writes,
        // and what `docs/cron.md` says is enough.
        get.many(tableName: 'loss_events', where: Eq('kind', 'loss')).ignore();
        mutate.delete.many(
          tableName: 'loss_events',
          where: Lt('created_at', DateTime.utc(2020)),
        );
      },
    );

    expect(
      _onlyGet(io)['jwt'],
      {'CRON': true},
      reason:
          'the read must default to the request identity. Before this, `jwt` '
          'was absent here and present on the delete below -- one cron, one '
          'scope, two identities, and only the read was denied.',
    );

    final deletes = io.sent
        .where((m) => '${m['path']}'.endsWith('.delete_record'))
        .toList();

    expect(
      deletes.single['jwt'],
      {'CRON': true},
      reason:
          'the half that already worked, asserted alongside the half that did '
          'not. A test covering only this one would have passed throughout and '
          'proved nothing -- which is exactly how the defect survived a green '
          'suite on both sides of the wire.',
    );
  });

  test('a firing from a timer created inside an outer scope reads as the cron '
      'too -- the nesting that scheduled crons actually run under', () async {
    // `_startCrons` runs inside the handler for `StartCronsRequest`, and
    // `cron.schedule` registers its timers there. A Dart timer fires in the
    // zone that created it, so every scheduled firing is still nested inside
    // startup however much later it happens. The identity has to come from the
    // INNER scope, for the same reason the queued mutation's parent id does
    // (see scheduled_cron_mutations_test.dart).
    late MessageHandler<CronRequest> handler;
    final fired = Completer<void>();
    final io = _FakeMessageIo();

    handler = MessageHandler<CronRequest>(
      fromUnknownRequest: CronRequest.fromRequest,
      onMessage: (request) async {
        Timer(const Duration(milliseconds: 5), () async {
          await handler.runWithParent(
            RunCronJobRequest(name: '_anti_spam_fan_out'),
            () async {
              get
                  .many(tableName: 'loss_events', where: Eq('kind', 'loss'))
                  .ignore();
            },
          );
          fired.complete();
        });
        return null;
      },
      io: io,
    );

    unawaited(handler.listen());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    addTearDown(io.dispose);

    io.push(StartCronsRequest().toJson());
    await fired.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      _onlyGet(io)['jwt'],
      {'CRON': true},
      reason:
          'the ambient identity must be rebound by the inner scope, not '
          'inherited from the one that started the scheduler',
    );
  });

  test('a read from a request carrying no identity stays anonymous -- the '
      'default is the request, not a blanket elevation', () async {
    final io = await _handle<UnknownRequest>(
      // No `jwt` key: `Request.fromJson` builds an `UnknownRequest` with a null
      // one, which is what an unauthenticated caller's request looks like.
      {'path': '${Request.prefix}.some_extension_hook', 'id': 'req-1'},
      (request) => request,
      () async {
        get.many(tableName: 'loss_events', where: Eq('kind', 'loss')).ignore();
      },
    );

    expect(
      _onlyGet(io).containsKey('jwt'),
      isFalse,
      reason:
          'inheriting the request identity must not become "every read is '
          'privileged". A null ambient JWT has to stay null on the wire, or '
          'this fix trades an over-restrictive read for an under-restrictive '
          'one -- much the worse direction.',
    );
  });

  test('an explicit jwt is still passed through, so a caller that already '
      'worked around this keeps working', () async {
    final io = await _handle(
      RunCronJobRequest(name: '_anti_spam_fan_out').toJson(),
      CronRequest.fromRequest,
      () async {
        get
            .many(
              tableName: 'loss_events',
              where: Eq('kind', 'loss'),
              jwt: CronJwt(),
            )
            .ignore();
      },
    );

    // The consumers' documented workaround was to pass the JWT at all four
    // call sites. That code must not now be silently ignored, or fixing this
    // would break the people who had already routed around it.
    //
    // The honest limit, recorded rather than asserted: `jwt: null` is
    // indistinguishable from "argument omitted" in Dart, so opting *out* of
    // the ambient identity is not expressible through this API. A read as
    // nobody from inside a cron needs a different signature than this one.
    expect(_onlyGet(io)['jwt'], {'CRON': true});
  });
}
