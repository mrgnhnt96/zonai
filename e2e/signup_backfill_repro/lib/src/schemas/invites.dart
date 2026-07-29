import 'package:zonai_signup_backfill_repro/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Invite {
  Invite({
    required this.id,
    required this.email,
    required this.createdAt,
    this.userId,
    this.updatedAt,
  });

  final InvitesId id;
  final String email;
  final String? userId;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class InviteTable extends Table<Invite> {
  InviteTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: InvitesId.new,
        generate: InvitesId.generate,
      ),
      email = $.text('email', (s) => s.email),
      userId = $.text('user_id', (s) => s.userId),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Invite fromRow(RowReader read) {
    return Invite(
      id: read(id),
      email: read(email),
      userId: read(userId),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<InvitesId> id;
  final TextColumn email;
  final ColumnType<String?> userId;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final invites = table('invites', InviteTable.new);
