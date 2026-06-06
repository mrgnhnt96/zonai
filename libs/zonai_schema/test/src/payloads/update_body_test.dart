import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/update/update.dart';

void main() {
  group('UpdateBody.toJson', () {
    test('includes updates in serialized body', () {
      const body = UpdateOneBody(
        table: 'items',
        where: Eq('id', 'abc'),
        updates: [
          ObjectUpdate({'title': 'Updated'}),
        ],
      );

      final json = body.toJson();
      expect(json['table'], 'items');
      expect(json['where'], isA<Map<String, dynamic>>());
      expect(json['limit'], 1);
      expect(json['updates'], [
        {
          'type': 'object',
          'object': {'title': 'Updated'},
        },
      ]);

      final restored = UpdateOneBody.fromJson(Map<String, dynamic>.from(json));
      expect(restored.table, body.table);
      expect(restored.updates, hasLength(1));
      expect(restored.updates.single, isA<ObjectUpdate>());
      expect(
        (restored.updates.single as ObjectUpdate).object['title'],
        'Updated',
      );
    });
  });
}
