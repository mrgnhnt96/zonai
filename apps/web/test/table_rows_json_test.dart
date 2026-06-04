import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/table_rows_json.dart';

void main() {
  group('apiWireObject', () {
    test('round-trips through jsonEncode for create payloads', () {
      final at = DateTime.utc(2024, 6, 1, 12, 0);
      final wire = apiWireObject({
        'title': 'Hello',
        'count': BigInt.parse('42'),
        'payload': Uint8List.fromList([1, 0, 1]),
        'created_at': at,
      });

      expect(() => jsonEncode(CreateBody(table: 'items', object: wire)), returnsNormally);
      expect(wire['count'], '42');
      expect(wire['created_at'], at.millisecondsSinceEpoch);
      expect(wire['payload'], base64Encode([1, 0, 1]));
    });
  });
}
