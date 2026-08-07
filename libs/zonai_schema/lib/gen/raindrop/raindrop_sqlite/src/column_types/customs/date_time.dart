// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension DateTimeColumnDefinition<R> on SchemaBuilder<R> {
  ColumnType<W> dateTime<W extends DateTime?>(
    String name,
    Field<R, W> field, {
    String? defaultValue,
  }) {
    return custom<DateTime, Object, W>(
      name,
      field,
      transformer: const DateTimeTransfomer(),
      sqlType: 'INTEGER',
      defaultValue: defaultValue,
    );
  }
}

class DateTimeTransfomer extends ColumnTransformer<DateTime, Object> {
  const DateTimeTransfomer();

  @override
  Object encode(DateTime input) => input.millisecondsSinceEpoch;

  // Storage/wire values arrive as epoch milliseconds (int, from sqlite or a
  // wire-conscious client) or an ISO-8601 string (the natural JSON encoding
  // of a timestamp, from a JSON create/update body). Accept both instead of
  // throwing a bare TypeError that surfaces as a 500. `.toLocal()` keeps both
  // forms decoding to the same representation the int path always returned.
  @override
  DateTime decode(Object input) => switch (input) {
    int ms => DateTime.fromMillisecondsSinceEpoch(ms),
    String iso =>
      (DateTime.tryParse(iso) ??
              (throw FormatException(
                'Invalid DateTime value: "$iso" is not epoch milliseconds or '
                'an ISO-8601 string',
              )))
          .toLocal(),
    _ => throw FormatException(
      'Invalid DateTime value: $input (${input.runtimeType})',
    ),
  };
}
