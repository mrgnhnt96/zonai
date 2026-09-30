import 'package:zonai_data_plane_access_repro/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A table whose `canView` is WIDER than its `viewScope`: any row may be
/// viewed or updated by anyone signed in, but a read is scoped to the
/// caller's own rows. The scope is the narrower statement, and every read
/// path -- including the rows a refused update reports back -- must honour it.
final class Board {
  Board({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.createdAt,
    this.updatedAt,
  });

  final BoardsId id;
  final String title;
  final String ownerId;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class BoardTable extends Table<Board> {
  BoardTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: BoardsId.new,
        generate: BoardsId.generate,
      ),
      title = $.text('title', (s) => s.title),
      ownerId = $.text('owner_id', (s) => s.ownerId),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Board fromRow(RowReader read) {
    return Board(
      id: read(id),
      title: read(title),
      ownerId: read(ownerId),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<BoardsId> id;
  final TextColumn title;
  final TextColumn ownerId;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final boards = table('boards', BoardTable.new);
