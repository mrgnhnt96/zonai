import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  group('CustomBody.toJson', () {
    test('round-trips table, where, and updates', () {
      const body = CustomBody(
        table: 'tins',
        where: Eq('id', 'abc'),
        updates: [
          ObjectUpdate({'status': 'reserved'}),
        ],
      );

      final json = body.toJson();
      expect(json['table'], 'tins');
      expect(json['where'], isA<Map<String, dynamic>>());
      expect(json['updates'], [
        {
          'type': 'object',
          'object': {'status': 'reserved'},
        },
      ]);

      final restored = CustomBody.fromJson(Map<String, dynamic>.from(json));
      expect(restored.table, body.table);
      expect(restored.where, isA<Eq>());
      expect(restored.updates, hasLength(1));
      expect(restored.updates.single, isA<ObjectUpdate>());
      expect(
        (restored.updates.single as ObjectUpdate).object['status'],
        'reserved',
      );
    });

    test('omits where when table-scoped (no target rows)', () {
      const body = CustomBody(table: 'tins');

      final json = body.toJson();
      expect(json.containsKey('where'), isFalse);

      final restored = CustomBody.fromJson(Map<String, dynamic>.from(json));
      expect(restored.where, isNull);
      expect(restored.updates, isEmpty);
    });
  });

  group('CustomOneBody', () {
    test('always carries limit 1 and requires where', () {
      const body = CustomOneBody(table: 'tins', where: Eq('id', 'abc'));

      expect(body.limit, 1);

      final json = body.toJson();
      expect(json['limit'], 1);
      expect(json['where'], isA<Map<String, dynamic>>());

      final restored = CustomOneBody.fromJson(Map<String, dynamic>.from(json));
      expect(restored.limit, 1);
      expect(restored.where, isA<Eq>());
    });
  });
}
