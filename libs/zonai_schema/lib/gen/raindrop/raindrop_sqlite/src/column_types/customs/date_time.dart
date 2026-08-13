// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Timestamps, stored as an INTEGER.
extension DateTimeColumnDefinition<R> on SchemaBuilder<R> {
  /// A [DateTime] column, stored as milliseconds since the Unix epoch.
  ///
  /// [defaultValue] is a [DateTime] like any other value for this column, not
  /// a raw SQL string -- it is encoded through [DateTimeTransformer] the same
  /// way a written value is, so the default cannot disagree with the storage
  /// format.
  ColumnType<W> dateTime<W extends DateTime?>(
    String name,
    Field<R, W> field, {
    ColumnOr<DateTime>? defaultValue,
  }) {
    return custom<DateTime, Object, W>(
      name,
      field,
      transformer: const DateTimeTransformer(),
      sqlType: 'INTEGER',
      defaultValue: defaultValue,
    );
  }
}

/// {@template date_time_transformer}
/// Encodes a [DateTime] as its [DateTime.millisecondsSinceEpoch] value.
/// {@endtemplate}
class DateTimeTransformer extends ColumnTransformer<DateTime, Object> {
  /// {@macro date_time_transformer}
  const DateTimeTransformer();

  @override
  Object encode(DateTime input) => input.millisecondsSinceEpoch;

  /// Storage/wire values arrive as epoch milliseconds (int, from sqlite or a
  /// wire-conscious client) or an ISO-8601 string (the natural JSON encoding
  /// of a timestamp, from a JSON create/update body). Accepting both avoids a
  /// bare `TypeError` surfacing as a 500. `.toLocal()` keeps both forms
  /// decoding to the same representation the int path always returned.
  @override
  DateTime decode(Object input) => switch (input) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        final String iso => (DateTime.tryParse(iso) ??
                (throw FormatException(
                  'Invalid DateTime value: "$iso" is not epoch milliseconds '
                  'or an ISO-8601 string',
                )))
            .toLocal(),
        _ => throw FormatException(
            'Invalid DateTime value: $input (${input.runtimeType})',
          ),
      };
}
