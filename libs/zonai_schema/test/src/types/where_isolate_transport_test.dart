@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A serialized [Where] has to survive being handed to `SendPort.send`.
///
/// `Mailman` has two transports and they accept different things. The process
/// worker gets `IpcCodec.encode(message)` — bytes, so any `List` implementation
/// serializes fine. The **isolate** worker gets `peer.send(message)`, the
/// message graph itself, and an isolate message may only contain the primitive
/// types plus *plain* `List`/`Map` instances. A view type like the `CastList`
/// returned by `.cast<Object>()` is "a regular instance" and is rejected.
///
/// That difference hid a real bug for a whole release. `serializeWhereValues`
/// ended in `.cast<Object>()`, so every `In`/`NotIn` clause threw
/// `ArgumentError` on any binary that spawns the isolate transport — which is
/// every released binary. It surfaced only when `_update` started keying its
/// read-back on an `In`, which put one on the update path of every request;
/// the tests that covered that change all ran over the process transport and
/// passed throughout.
///
/// So these assert the property directly, by *sending* through a real isolate
/// rather than by checking a `runtimeType` — a future serializer could
/// introduce a different unsendable type and a type check would not notice.
void main() {
  group('Where.toJson is isolate-sendable', () {
    late Isolate isolate;
    late SendPort peer;
    late StreamIterator<dynamic> inbox;
    late ReceivePort local;
    late Directory tempDir;

    // `Isolate.spawnUri`, not `Isolate.spawn`, and the difference is the whole
    // test. `spawn` reuses the current isolate *group*, where a message may
    // carry any object at all -- every case here passes against the unfixed
    // serializer under `spawn`. `spawnUri` loads a separate group, which is
    // what `Mailman` does (mailman.dart, `Isolate.spawnUri`) and what enforces
    // the sendable-types restriction. Written the wrong way first, and it sat
    // there green against the very bug it was added for.
    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('zonai_where_isolate_');
      final worker = File('${tempDir.path}/worker.dart')
        ..writeAsStringSync('''
import 'dart:isolate';

void main(List<String> args, SendPort send) {
  final port = ReceivePort();
  send.send(port.sendPort);
  port.listen((_) => send.send('ok'));
}
''');

      local = ReceivePort();
      inbox = StreamIterator<dynamic>(local.asBroadcastStream());
      isolate = await Isolate.spawnUri(worker.uri, const [], local.sendPort);
      expect(await inbox.moveNext(), isTrue);
      peer = inbox.current as SendPort;
    });

    tearDownAll(() {
      isolate.kill(priority: Isolate.immediate);
      local.close();
      tempDir.deleteSync(recursive: true);
    });

    /// Sends [where]'s wire form the way the isolate transport does.
    Future<void> expectSendable(Where where) async {
      final message = <String, dynamic>{
        'path': 'operations/list',
        'where': where.toJson(),
      };

      expect(
        () => peer.send(message),
        returnsNormally,
        reason:
            '${where.runtimeType}.toJson() put something in the message that '
            'an isolate message cannot carry',
      );

      expect(await inbox.moveNext(), isTrue);
      expect(inbox.current, 'ok');
    }

    test('In — the clause that was broken', () async {
      await expectSendable(In('id', <Object>['a_lst', 'b_lst']));
    });

    test('NotIn — same serializer, same exposure', () async {
      await expectSendable(NotIn('id', <Object>['a_lst']));
    });

    test('In with a single value', () async {
      await expectSendable(In('id', <Object>['only']));
    });

    test('In with non-string values', () async {
      await expectSendable(In('rank', <Object>[1, 2, 3]));
    });

    test('And/Or carrying an In nested inside', () async {
      await expectSendable(
        And([
          const Eq('place_id', 'p1'),
          In('id', <Object>['a_lst']),
        ]),
      );
    });

    test('Eq — the clause that always worked, as a control', () async {
      await expectSendable(const Eq('place_id', 'p1'));
    });
  });

  test('serializeWhereValues returns a plain List, not a view', () {
    // The type check is the diagnosis, not the gate — the sends above are the
    // gate. It is here so a failure says *why* rather than only *that*.
    final values = In('id', <Object>['a']).toJson()['values'];
    expect(values, isA<List<Object>>());
    expect(
      values.runtimeType.toString(),
      startsWith('List'),
      reason: 'a CastList (or any other view) is not isolate-sendable',
    );
  });
}
