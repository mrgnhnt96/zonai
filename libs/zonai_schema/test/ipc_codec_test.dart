// dart format width=100
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';

void main() {
  group('IpcCodec', () {
    test('round-trips a request-shaped map', () {
      final map = {
        'path': 'request/ping',
        'id': 'abc-123',
        'payload': {
          'nested': true,
          'count': 42,
          'items': [1, 'two', null],
        },
      };

      final frame = IpcCodec.encode(map);
      expect(frame[0], IpcCodec.magic0);
      expect(frame[1], IpcCodec.magic1);
      expect(frame[2], IpcCodec.version);

      final buffer = IpcFrameBuffer();
      final decoded = buffer.push(frame);
      expect(decoded, hasLength(1));
      expect(decoded.single['path'], 'request/ping');
      expect(decoded.single['id'], 'abc-123');
      expect(decoded.single['payload'], isA<Map<String, dynamic>>());
      final payload = decoded.single['payload'] as Map<String, dynamic>;
      expect(payload['nested'], isTrue);
      expect(payload['count'], 42);
      expect(payload['items'], [1, 'two', null]);
    });

    test('reassembles split chunks', () {
      final frame = IpcCodec.encode({'path': 'response/pong', 'id': 'x'});
      final mid = frame.length ~/ 2;
      final buffer = IpcFrameBuffer();
      expect(buffer.push(frame.sublist(0, mid)), isEmpty);
      final decoded = buffer.push(frame.sublist(mid));
      expect(decoded, hasLength(1));
      expect(decoded.single['path'], 'response/pong');
    });

    test('rejects stale JSON magic', () {
      final buffer = IpcFrameBuffer();
      expect(
        () => buffer.push(utf8Bytes('{"path":"request/ping"}\n')),
        throwsFormatException,
      );
    });

    test('clear drops partial frames', () {
      final frame = IpcCodec.encode({'path': 'request/ping', 'id': '1'});
      final buffer = IpcFrameBuffer();
      buffer.push(frame.sublist(0, 3));
      buffer.clear();
      expect(buffer.push(frame), hasLength(1));
    });

    test('encodes nested toJson objects like jsonEncode', () {
      final frame = IpcCodec.encode({
        'path': 'response/config',
        'id': '1',
        'payload': {'_probe': _Probe(name: 'nested')},
      });
      final decoded = IpcFrameBuffer().push(frame).single;
      final payload = decoded['payload'] as Map<String, dynamic>;
      expect(payload['_probe'], {'name': 'nested'});
    });
  });
}

class _Probe {
  _Probe({required this.name});
  final String name;
  Map<String, dynamic> toJson() => {'name': name};
}

Uint8List utf8Bytes(String s) => Uint8List.fromList(s.codeUnits);
