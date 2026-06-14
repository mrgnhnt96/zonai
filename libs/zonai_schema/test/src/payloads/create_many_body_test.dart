import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  group('CreateManyBody', () {
    test('round-trips through JSON', () {
      const body = CreateManyBody(
        table: 'tasks',
        objects: [
          {'title': 'a'},
          {'title': 'b', 'isComplete': true},
        ],
      );

      final restored = CreateManyBody.fromJson(body.toJson());

      expect(restored.table, 'tasks');
      expect(restored.objects, body.objects);
    });
  });
}
