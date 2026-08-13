// Members of the extension over the `events` table the docs invent.
import 'package:my_app/src/schemas/events.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class EventExtensions extends Extension<Event> {
  EventExtensions() : super(events);

  // <<body>>
}
