import 'package:test/test.dart';
import 'package:zonai_playground/src/schemas/items.dart';

void main() {
  test('Item can be constructed with only body', () {
    const body = 'minimal row';
    final item = Item(body: body);

    expect(item.body, body);
    expect(item.id, isNotNull);
    expect(item.description, isNull);
    expect(item.status, isNull);
    expect(item.updatedAt, isNull);
    expect(item.createdAt, isA<DateTime>());
  });
}
