import 'dart:convert';
import 'package:crypto/crypto.dart';

sealed class Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: $json');
    }

    return switch (parts[1]) {
      ItemsId._suffix => ItemsId(json),
      _ => throw ArgumentError('Invalid ID format: $json'),
    };
  }

  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ItemsId extends Id {
  const ItemsId(super.value);

  factory ItemsId.generate() => ItemsId(_generateId(_suffix));

  static const _suffix = 'it';
}

String _generateId(String suffix) {
  // generate hash (15 chars)
  final now = DateTime.now();
  final hash = sha256
      .convert(utf8.encode('$suffix:${now.toIso8601String()}'))
      .toString()
      .substring(0, 15);

  return '${hash}_${suffix}';
}
