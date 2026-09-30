import 'package:zonai_data_plane_access_repro/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The same shape as `notes`, but its row rules declare a `viewScope`, so a
/// read is filtered to the caller's own rows instead of refused.
final class JournalEntry {
  JournalEntry({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.createdAt,
    this.updatedAt,
  });

  final JournalId id;
  final String title;
  final String ownerId;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class JournalTable extends Table<JournalEntry> {
  JournalTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: JournalId.new,
        generate: JournalId.generate,
      ),
      title = $.text('title', (s) => s.title),
      ownerId = $.text('owner_id', (s) => s.ownerId),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  JournalEntry fromRow(RowReader read) {
    return JournalEntry(
      id: read(id),
      title: read(title),
      ownerId: read(ownerId),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<JournalId> id;
  final TextColumn title;
  final TextColumn ownerId;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final journal = table('journal', JournalTable.new);
