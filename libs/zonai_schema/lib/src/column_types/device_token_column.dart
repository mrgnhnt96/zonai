import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// A push notification device token, stored as opaque `TEXT`.
///
/// Declaring a column with this type is what lets Zonai find it: `push`
/// resolves the recipient set by looking the named column up in
/// `schemaShapes()` and refusing anything that is not
/// [ColumnShapeKind.deviceToken]. It is also the column Zonai clears when FCM
/// reports the token permanently rejected — see `PushConfig`.
///
/// Nothing else about the table is Zonai's business: the table name, the
/// primary key, and every other column stay the app's.
extension DeviceTokenColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> deviceToken<W extends String?>(String name, Field<S, W> field) {
    return custom<String, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const DeviceTokenTransformer(),
    );
  }
}

class DeviceTokenTransformer extends ColumnTransformer<String, String> {
  const DeviceTokenTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
