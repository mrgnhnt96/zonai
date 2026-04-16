import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

/// Tiny table used only by this example ([Table.name] is `demo_widgets`).
class DemoWidget extends Schema<DemoWidget> {
  DemoWidget({
    int? id,
    required String title,
  }) : id = $.integer('id', (s) => s.id, id).primaryKey(autoIncrement: true),
       title = $.text('title', (s) => s.title, title);

  final IntColumn? id;
  final TextColumn title;

  static const $ = SchemaBuilder<DemoWidget>();
}

final demoWidgets = sqliteTable(
  'demo_widgets',
  () => DemoWidget(
    id: fakes.primaryKey(),
    title: fakes.text(),
  ),
);
