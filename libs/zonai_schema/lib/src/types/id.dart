import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

abstract interface class Id {
  const Id();

  String get value;

  static String generate([String? suffix]) {
    final random = Random.secure();
    final nonce = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = sha256
        .convert([
          if (suffix case final suffix?)
            ...utf8.encode(suffix)
          else
            ...utf8.encode(DateTime.now().microsecondsSinceEpoch.toString()),
          ...nonce,
        ])
        .toString()
        .substring(0, 15);

    return [hash, ?suffix].join('_');
  }

  bool operator ==(Object other) => other is Id && other.value == value;

  int get hashCode => value.hashCode;
}

class UnknownId implements Id {
  const UnknownId(this.value);

  @override
  final String value;
}
