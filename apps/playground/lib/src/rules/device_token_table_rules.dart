import 'package:zonai_playground/src/schemas/device_tokens.dart';
import 'package:zonai_schema/zonai_schema.dart';

DeviceTokenTableRules main() => DeviceTokenTableRules();

/// Device registrations are admin-only reading.
///
/// A token is a capability: anyone holding one can be sent a notification, and
/// nothing else about the row is interesting enough to make listing it safe for
/// an ordinary signed-in user. Writes are deliberately NOT overridden —
/// `BaseTableRules` already denies them without `jwt.admin.canEdit`.
final class DeviceTokenTableRules
    extends TableRules<DeviceTokenTable, DeviceToken> {
  DeviceTokenTableRules() : super(deviceTokens);

  @override
  Future<bool> canView(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;

  @override
  Future<bool> canList(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
}
