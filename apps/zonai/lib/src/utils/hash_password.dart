import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';

/// Argon2id password hashing with a random salt per credential.
///
/// Pass [appPepper] to [hash] and [verify]; it must **never** be persisted in
/// the database.
///
/// [hash] returns `<saltBase64>.<digestBase64>` — only the salt and digest are
/// stored. Argon2 **m**, **t**, **p**, and digest length come from this
/// instance; [verify] must use a [HashPassword] constructed with the same
/// parameters that produced the stored value.
///
/// Default Argon2id parameters (memory cost in kibibytes).
///
/// Tuned for \~OWASP "single-server web app" guidance (~19 MiB, time >= 2).
/// Adjust via [HashPassword] constructor if your threat model differs.
final class HashPassword {
  const HashPassword({
    this.memoryKiB = 19456,
    this.iterations = 3,
    this.parallelism = 1,
    this.hashLength = 32,
    this.saltLength = 16,
  }) : assert(memoryKiB >= 8, 'memoryKiB must be at least 8'),
       assert(iterations >= 1, 'iterations must be at least 1'),
       assert(parallelism >= 1, 'parallelism must be at least 1'),
       assert(
         hashLength >= Argon2BytesGenerator.MIN_OUTLEN,
         'hashLength must be at least ${Argon2BytesGenerator.MIN_OUTLEN}',
       ),
       assert(saltLength >= 8, 'saltLength must be at least 8');

  /// Argon2 `m` cost (kibibytes).
  final int memoryKiB;

  /// Argon2 `t` cost (iterations / passes).
  final int iterations;

  /// Argon2 `p` cost (parallelism / lanes).
  final int parallelism;

  /// Digest length in bytes.
  final int hashLength;

  /// Random salt length in bytes (from [Random.secure]) when [salt] is omitted.
  final int saltLength;

  /// Returns `<saltBase64>.<digestBase64>` for storage ([appPepper] is never included).
  ///
  /// For tests only, pass [salt] for deterministic output; omit in production.
  Future<String> hash({
    required String password,
    required String appPepper,
    List<int>? salt,
  }) async {
    final Uint8List resolvedSalt;
    if (salt == null) {
      resolvedSalt = generateSecureSalt(saltLength);
    } else {
      if (salt.length < 8) {
        throw ArgumentError.value(salt, 'salt', 'must be at least 8 bytes');
      }
      resolvedSalt = Uint8List.fromList(salt);
    }

    final digest = _computeDigest(
      password: password,
      pepper: appPepper,
      salt: resolvedSalt,
    );
    return _encodeStored(salt: resolvedSalt, hash: digest);
  }

  /// Returns whether [appPepper] and [rawPassword] reproduce [passwordHash],
  /// using Argon2 parameters from **this** instance and the salt from
  /// [passwordHash].
  Future<bool> verify({
    required String appPepper,
    required String passwordHash,
    required String rawPassword,
  }) async {
    final _StoredHashRecord parsed;
    try {
      parsed = _decodeStored(passwordHash);
    } on FormatException {
      return false;
    }

    if (parsed.salt.length < 8) {
      return false;
    }

    if (parsed.hash.length != hashLength ||
        parsed.hash.length < Argon2BytesGenerator.MIN_OUTLEN) {
      return false;
    }

    final expected = _computeDigest(
      password: rawPassword,
      pepper: appPepper,
      salt: parsed.salt,
    );

    return _constantTimeBytesEqual(expected, parsed.hash);
  }

  Uint8List _computeDigest({
    required String password,
    required String pepper,
    required Uint8List salt,
  }) {
    final params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: iterations,
      memory: memoryKiB,
      lanes: parallelism,
    );

    final argon = Argon2BytesGenerator()..init(params);
    final passwordBytes = _passwordAndPepperBytes(password, pepper);

    final result = Uint8List(hashLength);
    argon.generateBytes(passwordBytes, result, 0, result.length);
    return result;
  }

  Uint8List _passwordAndPepperBytes(String password, String pepper) {
    final p = utf8.encode(password);
    final s = utf8.encode(pepper);
    final out = Uint8List(4 + p.length + 4 + s.length);
    final view = ByteData.sublistView(out);
    view.setUint32(0, p.length, Endian.big);
    out.setRange(4, 4 + p.length, p);
    view.setUint32(4 + p.length, s.length, Endian.big);
    out.setRange(8 + p.length, 8 + p.length + s.length, s);
    return out;
  }

  Uint8List generateSecureSalt(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  String _encodeStored({required Uint8List salt, required Uint8List hash}) =>
      '${base64Encode(salt)}.${base64Encode(hash)}';

  _StoredHashRecord _decodeStored(String encoded) {
    final dot = encoded.indexOf('.');
    if (dot <= 0 || dot >= encoded.length - 1) {
      throw FormatException('Expected <saltBase64>.<digestBase64>');
    }
    final saltB64 = encoded.substring(0, dot);
    final hashB64 = encoded.substring(dot + 1);
    if (encoded.indexOf('.', dot + 1) != -1) {
      throw FormatException('Unexpected extra segments');
    }

    List<int> saltBytes;
    List<int> hashBytes;
    try {
      saltBytes = base64.decode(saltB64);
      hashBytes = base64.decode(hashB64);
    } on FormatException {
      throw FormatException('Invalid base64');
    }

    return _StoredHashRecord(
      salt: Uint8List.fromList(saltBytes),
      hash: Uint8List.fromList(hashBytes),
    );
  }

  bool _constantTimeBytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

final class _StoredHashRecord {
  const _StoredHashRecord({required this.salt, required this.hash});

  final Uint8List salt;
  final Uint8List hash;
}
