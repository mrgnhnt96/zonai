// A schema file declaring a table with a `deviceToken` column -- the shape
// docs/push.md shows when the subject is *how a token column is declared*
// rather than what a hook does with it.
//
// The row class lives here rather than being imported for the same reason
// schema-file.dart's does: the fragment declares the table for it, and
// importing the playground's would drag in the playground's ids as well.
import 'package:my_app/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class DeviceToken {
  const DeviceToken({
    required this.id,
    required this.userId,
    required this.token,
    required this.platform,
  });

  final UsersId id;
  final String userId;

  /// Nullable, and it has to be: `OnPermanentRejection.clearColumn` — the
  /// default — writes null here when FCM reports the token dead. A
  /// non-nullable column would make the framework's own default prune fail.
  final String? token;

  final String platform;
}

// <<body>>
