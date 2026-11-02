// dart format width=100
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:revali_client/revali_client.dart' show HttpPackageClient;
import 'package:test/test.dart';
import 'package:zonai_client/gen/client.dart' show Server;
import 'package:zonai_client/zonai_client.dart';

/// `db.listen` against a real socket that writes `/db/stream*` messages the way
/// the network delivers them: one message in several reads, or several
/// messages in one read. Each write is flushed and followed by a pause so the
/// client reads it on its own.
void main() {
  late HttpServer server;
  late Map<String, List<String>> writes;
  late ZonaiClient client;

  setUp(() async {
    writes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      for (final chunk in writes[request.uri.path] ?? const <String>[]) {
        request.response.add(utf8.encode(chunk));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await request.response.close();
    });
    client = ZonaiClient(baseUrl: Uri.parse('http://127.0.0.1:${server.port}'));
  });

  tearDown(() => server.close(force: true));

  final rows = [
    for (var i = 0; i < 9; i++) {'id': 'row-$i', 'title': 'Item $i ' * 40},
  ];

  List<String> splitInThree(String message) {
    final cut = message.length ~/ 3;
    return [message.substring(0, cut), message.substring(cut, cut * 2), message.substring(cut * 2)];
  }

  group('a message split across reads', () {
    test('listen.list yields the whole list', () async {
      writes['/db/stream/list'] = splitInThree(jsonEncode({'data': rows}));

      final lists = await client.db.listen
          .list(
            body: const StreamListBody(table: 'items'),
            fromJson: (row) => row,
          )
          .toList();

      expect(lists, [rows]);
    });

    test('listen.one yields the whole row', () async {
      writes['/db/stream'] = splitInThree(jsonEncode({'data': rows.first}));

      final found = await client.db.listen
          .one(
            body: const StreamBody(table: 'items', where: Eq('id', 'row-0')),
            fromJson: (row) => row,
          )
          .toList();

      expect(found, [rows.first]);
    });

    test('listen.count yields the count', () async {
      writes['/db/stream/count'] = ['{"da', 'ta":4', '2}'];

      final counts = await client.db.listen
          .count(
            body: const StreamCountBody(table: 'items', where: Eq('done', false)),
          )
          .toList();

      expect(counts, [42]);
    });
  });

  group('several messages in one read', () {
    test('listen.list yields each list', () async {
      writes['/db/stream/list'] = [
        jsonEncode({'data': rows.take(1).toList()}) + jsonEncode({'data': rows.take(2).toList()}),
      ];

      final lists = await client.db.listen
          .list(
            body: const StreamListBody(table: 'items'),
            fromJson: (row) => row,
          )
          .toList();

      expect(lists, [rows.take(1).toList(), rows.take(2).toList()]);
    });

    test('listen.one yields each row', () async {
      writes['/db/stream'] = [
        jsonEncode({'data': rows[0]}) + jsonEncode({'data': rows[1]}),
      ];

      final found = await client.db.listen
          .one(
            body: const StreamBody(table: 'items', where: Eq('id', 'row-0')),
            fromJson: (row) => row,
          )
          .toList();

      expect(found, [rows[0], rows[1]]);
    });

    test('listen.count yields each count', () async {
      writes['/db/stream/count'] = ['{"data":1}{"data":2}{"data":3}'];

      final counts = await client.db.listen
          .count(
            body: const StreamCountBody(table: 'items', where: Eq('done', false)),
          )
          .toList();

      expect(counts, [1, 2, 3]);
    });
  });

  test('a message the stream ends inside is reported, not dropped silently', () async {
    final reported = <Object>[];
    final server_ = Server(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      client: HttpPackageClient(
        interceptors: [StreamFramingInterceptor(onError: (url, error, _) => reported.add(error))],
      ),
    );
    final custom = ZonaiClient.server(server: server_);
    writes['/db/stream/count'] = ['{"data":1}{"data":'];

    final counts = await custom.db.listen
        .count(
          body: const StreamCountBody(table: 'items', where: Eq('done', false)),
        )
        .toList();

    expect(counts, [1]);
    expect(reported, [isA<FormatException>()]);
    expect(
      server_.client.interceptors.whereType<StreamFramingInterceptor>(),
      hasLength(1),
      reason: 'the client keeps the one it was given instead of adding its own',
    );
  });
}
