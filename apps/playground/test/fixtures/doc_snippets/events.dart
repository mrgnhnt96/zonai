// Stand-in for the `events` table the docs invent for the beforeUpdate
// validation example. See tasks.dart for why these fixtures exist and when to
// extend them.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Event {
  const Event({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
  });

  final EventsId id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
}

final class EventTable extends Table<Event> {
  EventTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: EventsId.new,
        generate: EventsId.generate,
      ),
      title = $.text('title', (s) => s.title),
      startDate = $.dateTime('start_date', (s) => s.startDate),
      endDate = $.dateTime('end_date', (s) => s.endDate);

  @override
  Event fromRow(RowReader read) => Event(
    id: read(id),
    title: read(title),
    startDate: read(startDate),
    endDate: read(endDate),
  );

  final IdColumn<EventsId> id;
  final TextColumn title;
  final DateTimeColumn startDate;
  final DateTimeColumn endDate;
}

final events = table('events', EventTable.new);
