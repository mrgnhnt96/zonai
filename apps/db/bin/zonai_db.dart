import 'package:zonai_db/zonai_db.dart';

Future<void> main() async {
  final db = await openZonaiDatabase();

  final now = DateTime.now();
  final inserted = await db
      .insert(into: items)
      .values([Item(body: 'Hello from zonai_db', createdAt: now)])
      .returning();

  print('Saved: $inserted');

  final rows = await db.select().from(items);
  print('All rows: $rows');

  await db.close();
}
