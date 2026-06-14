import 'package:zonai_schema/zonai_schema.dart';

class CronEntry {
  const CronEntry({
    required this.id,
    required this.name,
    required this.started,
    this.error,
    this.stackTrace,
    this.failed,
    this.completed,
  });

  CronEntry.create({required this.name})
    : id = CronsId.generate(),
      started = .now(),
      completed = null,
      failed = null,
      error = null,
      stackTrace = null;

  final CronsId id;
  final String name;
  final DateTime started;
  final DateTime? completed;
  final DateTime? failed;
  final String? error;
  final String? stackTrace;
}

class CronsId implements Id {
  const CronsId(this.value);
  static CronsId generate() => CronsId(Id.generate('cr'));

  @override
  final String value;

  @override
  String toString() => value;
}

class CronsTable extends Table<CronEntry> {
  CronsTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: CronsId.new,
        generate: CronsId.generate,
      ),
      name = $.text('name', (s) => s.name),
      started = $.createdAt('started', (s) => s.started),
      completed = $.dateTime('completed', (s) => s.completed),
      failed = $.dateTime('failed', (s) => s.failed),
      error = $.text('error', (s) => s.error),
      stackTrace = $.text('stack_trace', (s) => s.stackTrace);

  final IdColumn<CronsId> id;
  final TextColumn name;
  final DateTimeColumn started;
  final ColumnType<DateTime?> failed;
  final ColumnType<DateTime?> completed;
  final ColumnType<String?> error;
  final ColumnType<String?> stackTrace;

  @override
  CronEntry fromRow(RowReader read) {
    return CronEntry(
      id: read(id),
      name: read(name),
      started: read(started),
      completed: read(completed),
      failed: read(failed),
      error: read(error),
      stackTrace: read(stackTrace),
    );
  }
}

final crons = table('_cron_jobs', CronsTable.new, (t) {
  index('cron_name_index').on(t.name);
  index('cron_incomplete_index').on(t.name, t.completed, t.failed);
});
