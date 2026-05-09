import 'dart:convert';
import 'dart:math';

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
      UsersId._suffix => UsersId(json),
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

class UsersId extends Id {
  const UsersId(super.value);

  factory UsersId.generate() => UsersId(_generateId(_suffix));

  static const _suffix = 'us';
}

String _generateId(String suffix) {
  final random = Random.secure();
  final nonce = List<int>.generate(16, (_) => random.nextInt(256));
  final hash = sha256
      .convert([...utf8.encode(suffix), ...nonce])
      .toString()
      .substring(0, 15);

  return '${hash}_${suffix}';
}
