import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

abstract interface class Id {
  const Id();

  String get value;

  // TODO: add prefix + suffix
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

  @override
  String toString() => value;
}

class UnknownId implements Id {
  const UnknownId(this.value);

  @override
  final String value;

  // `implements Id` only takes on the interface's member *signatures*, not
  // Id's own operator==/hashCode bodies above — Dart doesn't inherit
  // concrete implementations through `implements`, only through `extends`/
  // mixins. Without this override, two UnknownIds built from the same
  // string down two different paths (e.g. Jwt.userId decoded from a token
  // vs. an ownerId column read back from a row) compare unequal, since the
  // inherited default falls back to identical()-based Object equality.
  // Found while adding ownership checks elsewhere that rely on exactly
  // this comparison (`jwt.userId == row.ownerId`) — the same comparison
  // PhotoRowRules.canUpdate/canDelete already make, so this was a real,
  // pre-existing bug there too, not just in new code.
  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
