// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:typed_data';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Arbitrary-precision integers, stored as a BLOB.
extension BigIntColumnDefinition<R> on SchemaBuilder<R> {
  /// A [BigInt] column: one sign byte, then the magnitude big-endian.
  ColumnType<W> bigInt<W extends BigInt?>(
    String name,
    Field<R, W> field, {
    ColumnOr<BigInt>? defaultValue,
  }) {
    return custom<BigInt, Object, W>(
      name,
      field,
      transformer: const BigIntTransformer(),
      sqlType: 'BLOB',
      defaultValue: defaultValue,
    );
  }
}

/// {@template big_int_transformer}
/// Encodes a [BigInt] as one sign byte followed by big-endian magnitude
/// bytes, so values of any size round-trip exactly.
/// {@endtemplate}
class BigIntTransformer extends ColumnTransformer<BigInt, Object> {
  /// {@macro big_int_transformer}
  const BigIntTransformer();

  @override
  Uint8List encode(BigInt input) {
    var magnitude = input.abs();
    final bytes = <int>[];
    while (magnitude > BigInt.zero) {
      bytes.add((magnitude & BigInt.from(0xff)).toInt());
      magnitude >>= 8;
    }
    return Uint8List.fromList([
      if (input.isNegative) 1 else 0,
      ...bytes.reversed,
    ]);
  }

  /// Storage/wire values arrive as the encoded BLOB (a `Uint8List` from
  /// sqlite, or a plain `List<int>` once it has been through a JSON/msgpack
  /// round-trip) or as a bare integer from a JSON create/update body. Accept
  /// all three rather than throwing a bare `TypeError` that surfaces as a 500.
  @override
  BigInt decode(Object input) => switch (input) {
        final int value => BigInt.from(value),
        final Uint8List bytes => _decodeBlob(bytes),
        final List<int> bytes => _decodeBlob(Uint8List.fromList(bytes)),
        _ => throw FormatException(
            'Invalid BigInt value: $input (${input.runtimeType})',
          ),
      };

  BigInt _decodeBlob(Uint8List input) {
    var value = BigInt.zero;
    for (final byte in input.skip(1)) {
      value = (value << 8) | BigInt.from(byte);
    }
    return input.first == 1 ? -value : value;
  }
}
