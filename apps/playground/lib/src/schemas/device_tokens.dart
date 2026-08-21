import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// One row per device, the shape `docs/push.md` recommends.
///
/// Local demo fixture for the dashboard's row-selection send action: the
/// dashboard offers it exactly when a table declares a `deviceToken` column,
/// and reads each row's transport from a `platform` column when there is one.
final class DeviceToken {
  const DeviceToken({
    required this.id,
    required this.userId,
    required this.label,
    required this.token,
    required this.platform,
    required this.createdAt,
  });

  final UsersId id;
  final String userId;
  final String label;

  /// Nullable, and it has to be: `OnPermanentRejection.clearColumn` — the
  /// default — writes null here when the transport reports the token dead.
  final String? token;

  final String platform;
  final DateTime createdAt;
}

final class DeviceTokenTable extends Table<DeviceToken> {
  DeviceTokenTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: UsersId.new,
        generate: UsersId.generate,
      ),
      userId = $.text('user_id', (s) => s.userId),
      label = $.text('label', (s) => s.label),
      token = $.deviceToken('token', (s) => s.token),
      platform = $.text('platform', (s) => s.platform),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  @override
  DeviceToken fromRow(RowReader read) => DeviceToken(
    id: read(id),
    userId: read(userId),
    label: read(label),
    token: read(token),
    platform: read(platform),
    createdAt: read(createdAt),
  );

  final IdColumn<UsersId> id;
  final TextColumn userId;
  final TextColumn label;
  final ColumnType<String?> token;
  final TextColumn platform;
  final DateTimeColumn createdAt;
}

final deviceTokens = table('device_tokens', DeviceTokenTable.new);
