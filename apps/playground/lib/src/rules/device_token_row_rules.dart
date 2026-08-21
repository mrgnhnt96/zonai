import 'package:zonai_playground/src/schemas/device_tokens.dart';
import 'package:zonai_schema/zonai_schema.dart';

DeviceTokenRowRules main() => DeviceTokenRowRules();

/// Same gate as the table: an admin reads a device row, nobody else does.
class DeviceTokenRowRules extends RowRules<DeviceTokenTable, DeviceToken> {
  DeviceTokenRowRules() : super(deviceTokens);

  @override
  Future<bool> canView(Jwt? jwt, DeviceToken row) async =>
      jwt?.admin.isAdmin ?? false;
}
