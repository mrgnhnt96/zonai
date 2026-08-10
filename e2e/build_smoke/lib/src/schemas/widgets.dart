import 'package:zonai_build_smoke/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Widget {
  Widget({required this.id, required this.name, required this.createdAt});

  final WidgetsId id;
  final String name;
  final DateTime createdAt;
}

final class WidgetTable extends Table<Widget> {
  WidgetTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: WidgetsId.new,
        generate: WidgetsId.generate,
      ),
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  @override
  Widget fromRow(RowReader read) {
    return Widget(id: read(id), name: read(name), createdAt: read(createdAt));
  }

  final IdColumn<WidgetsId> id;
  final TextColumn name;
  final DateTimeColumn createdAt;
}

final widgets = table('widgets', WidgetTable.new);
