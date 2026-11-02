// dart format width=100
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_client/src/utils/json_value_framer.dart';

void main() {
  Future<List<String>> frame(List<String> chunks) => Stream<List<int>>.fromIterable(
    chunks.map(utf8.encode),
  ).transform(const JsonValueFramer()).map(utf8.decode).toList();

  test('joins one message split across chunks', () async {
    final message = jsonEncode({
      'data': [
        for (var i = 0; i < 9; i++) {'id': i, 'name': 'row $i' * 40},
      ],
    });
    final cut = message.length ~/ 3;

    expect(
      await frame([
        message.substring(0, cut),
        message.substring(cut, cut * 2),
        message.substring(cut * 2),
      ]),
      [message],
    );
  });

  test('splits several messages in one chunk', () async {
    expect(await frame(['{"data":1}{"data":[2]} {"data":{"a":3}}\n']), [
      '{"data":1}',
      '{"data":[2]}',
      '{"data":{"a":3}}',
    ]);
  });

  test('handles a chunk that ends one message and starts the next', () async {
    expect(await frame(['{"data":1}{"da', 'ta":2}']), ['{"data":1}', '{"data":2}']);
  });

  test('ignores brackets, quotes and escapes inside strings', () async {
    const message = r'{"data":{"s":"} ] { [ \" \\","t":"\\"}}';
    final bytes = utf8.encode(message);
    final chunks = [
      for (final byte in bytes) utf8.decode([byte]),
    ];

    expect(await frame(chunks), [message]);
  });

  test('keeps multi-byte characters whole when a chunk cuts through one', () async {
    const message = '{"data":{"name":"Zoë 🦊"}}';
    final bytes = utf8.encode(message);
    final cut = bytes.indexOf(0xC3) + 1;

    final framed = await Stream<List<int>>.fromIterable([
      bytes.sublist(0, cut),
      bytes.sublist(cut),
    ]).transform(const JsonValueFramer()).map(utf8.decode).toList();

    expect(framed, [message]);
  });

  test('reports a stream that ends inside a message', () async {
    final events = <Object>[];
    final done = Completer<void>();
    Stream<List<int>>.fromIterable([utf8.encode('{"data":1}{"data":')])
        .transform(const JsonValueFramer())
        .listen(
          (chunk) => events.add(utf8.decode(chunk)),
          onError: events.add,
          onDone: done.complete,
        );
    await done.future;

    expect(events, ['{"data":1}', isA<FormatException>()]);
  });

  test('reports bytes between messages once and frames the next message', () async {
    final events = <Object>[];
    final done = Completer<void>();
    Stream<List<int>>.fromIterable([utf8.encode('{"data":1}oops{"data":2}')])
        .transform(const JsonValueFramer())
        .listen(
          (chunk) => events.add(utf8.decode(chunk)),
          onError: events.add,
          onDone: done.complete,
        );
    await done.future;

    expect(events, ['{"data":1}', isA<FormatException>(), '{"data":2}']);
  });
}
