// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:typed_data';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension BigIntColumnDefinition<R> on SchemaBuilder<R> {
  ColumnType<W> bigInt<W extends BigInt?>(String name, Field<R, W> field) {
    return custom<BigInt, Object, W>(
      name,
      field,
      transformer: const BigIntTransformer(),
      sqlType: 'BLOB',
    );
  }
}

class BigIntTransformer extends ColumnTransformer<BigInt, Object> {
  const BigIntTransformer();

  @override
  Uint8List encode(BigInt input) => Uint8List.fromList(
        input.toRadixString(2).split('').map(int.parse).toList(),
      );

  @override
  BigInt decode(Object input) => switch (input) {
        int value => BigInt.from(value),
        Uint8List bytes => _decodeBlob(bytes),
        List<int> bytes => _decodeBlob(bytes),
        _ => throw ArgumentError.value(
            input,
            'input',
            'Unsupported BigInt storage type',
          ),
      };

  BigInt _decodeBlob(List<int> bytes) => BigInt.parse(bytes.join(), radix: 2);
}
