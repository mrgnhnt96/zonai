import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';
import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai/src/native/argon2_ffi.dart' as argon2_ffi;
import 'package:zonai/src/native/argon2_native.dart';

/// Argon2id password hashing with a random salt per credential.
///
/// In production, secrets come from [configResolver] (including
/// [AppConfig.previousPasswordSecrets] during rotation). For tests, pass
/// [passwordSecret] and optionally [previousPasswordSecrets]. Secrets must
/// **never** be persisted in the database.
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
  HashPassword({
    String? passwordSecret,
    List<String> previousPasswordSecrets = const [],
    this.memoryKiB = 19456,
    this.iterations = 3,
    this.parallelism = 1,
    this.hashLength = 32,
    this.saltLength = 16,
  }) : _explicitPasswordSecret = passwordSecret,
       _explicitPreviousPasswordSecrets = previousPasswordSecrets,
       assert(memoryKiB >= 8, 'memoryKiB must be at least 8'),
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

  final String? _explicitPasswordSecret;
  final List<String> _explicitPreviousPasswordSecrets;

  List<String>? _cachedPasswordSecretsForVerify;

  Future<List<String>> _passwordSecretsForVerify() async {
    if (_cachedPasswordSecretsForVerify case final cached?) {
      return cached;
    }
    if (_explicitPasswordSecret == null &&
        _explicitPreviousPasswordSecrets.isNotEmpty) {
      throw StateError(
        'previousPasswordSecrets is only valid with passwordSecret when not using config',
      );
    }
    if (_explicitPasswordSecret case final explicit?) {
      return _cachedPasswordSecretsForVerify = [
        explicit,
        ..._explicitPreviousPasswordSecrets,
      ];
    }
    final config = await configResolver.resolve();
    return _cachedPasswordSecretsForVerify = List<String>.unmodifiable(
      config.passwordSecretsForVerify,
    );
  }

  Future<String> get passwordSecret async =>
      (await _passwordSecretsForVerify()).first;

  /// Returns `<saltBase64>.<digestBase64>` for storage ([passwordSecret] is never included).
  ///
  /// For tests only, pass [salt] for deterministic output; omit in production.
  Future<String> hash({required String password, List<int>? salt}) async {
    final Uint8List resolvedSalt;
    if (salt == null) {
      resolvedSalt = generateSecureSalt(saltLength);
    } else {
      if (salt.length < 8) {
        throw ArgumentError.value(salt, 'salt', 'must be at least 8 bytes');
      }
      resolvedSalt = Uint8List.fromList(salt);
    }

    final digest = await _digestOffMainIsolate(
      password: password,
      secret: await passwordSecret,
      salt: resolvedSalt,
    );
    return _encodeStored(salt: resolvedSalt, hash: digest);
  }

  /// Returns whether [rawPassword] reproduces [passwordHash] for some secret in
  /// [AppConfig.passwordSecretsForVerify] (or explicit constructor secrets),
  /// using Argon2 parameters from **this** instance and the salt from
  /// [passwordHash].
  Future<bool> verify({
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

    for (final secret in await _passwordSecretsForVerify()) {
      final expected = await _digestOffMainIsolate(
        password: rawPassword,
        secret: secret,
        salt: parsed.salt,
      );
      if (_constantTimeBytesEqual(expected, parsed.hash)) {
        return true;
      }
    }
    return false;
  }

  /// Runs the Argon2 digest on a separate isolate. Argon2 is deliberately
  /// CPU-heavy (that's what makes it resistant to brute-forcing); computing
  /// it inline would block this isolate's event loop for the full ~100-200ms
  /// cost on every hash/verify, stalling every other in-flight request
  /// (list/create/etc.) on the same isolate for that window. `Isolate.run`
  /// keeps that cost off the request-handling isolate and lets concurrent
  /// hashes actually run in parallel across cores instead of queueing.
  Future<Uint8List> _digestOffMainIsolate({
    required String password,
    required String secret,
    required Uint8List salt,
  }) async {
    // Resolved here, on the calling isolate, because it needs the `fs`
    // scoped_deps provider -- a spawned isolate has no Zone/scope context
    // to read that from. Only the resulting plain path string crosses the
    // isolate boundary below.
    final nativeLibraryPath = await _cachedNativeLibraryPath();

    return Isolate.run(
      () => _argon2Digest(
        password: password,
        secret: secret,
        salt: salt,
        iterations: iterations,
        memoryKiB: memoryKiB,
        parallelism: parallelism,
        hashLength: hashLength,
        nativeLibraryPath: nativeLibraryPath,
      ),
    );
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

/// Resolves once (via the `fs` scoped_deps provider, so this must run on a
/// isolate that actually has a scope -- never inside `Isolate.run`) and
/// caches the native Argon2 library's path for the lifetime of this
/// isolate. `null` means resolution failed (not built, unsupported
/// platform, etc.); cached too, so every hash/verify call doesn't retry a
/// failing filesystem lookup.
Future<String?>? _nativeLibraryPathFuture;

Future<String?> _cachedNativeLibraryPath() {
  return _nativeLibraryPathFuture ??= resolveArgon2NativeLibraryPath().then(
    (path) => path,
    onError: (Object _, StackTrace __) => null,
  );
}

/// Top-level (not an instance method) so `Isolate.run` can send it to a
/// fresh isolate without dragging the `HashPassword` instance along.
///
/// Tries the native (libsodium) path first -- same standardized Argon2id
/// algorithm, same output for the same inputs (verified byte-for-byte
/// against the pure-Dart path in hash_password_test.dart), but backed by
/// compiled C instead of interpreted Dart: ~35ms vs ~240ms per hash at
/// default cost parameters on the machine this was measured on. Falls
/// back to the pure-Dart implementation when:
///  - `parallelism != 1`: libsodium's simplified `crypto_pwhash` has no
///    lanes parameter, so it can't reproduce output for a non-default
///    parallelism.
///  - [nativeLibraryPath] is null, or `dlopen`/hashing it fails (e.g. a
///    dev checkout that hasn't run `scripts argon2 gen` yet, or an
///    unsupported platform) -- the fallback keeps that a slow-but-working
///    degradation, not a crash.
Future<Uint8List> _argon2Digest({
  required String password,
  required String secret,
  required Uint8List salt,
  required int iterations,
  required int memoryKiB,
  required int parallelism,
  required int hashLength,
  required String? nativeLibraryPath,
}) async {
  if (parallelism == 1 && nativeLibraryPath != null) {
    try {
      argon2_ffi.install(nativeLibraryPath);
      return argon2_ffi.cryptoPwhashArgon2id(
        password: _passwordAndSecretBytes(password, secret),
        salt: salt,
        outLen: hashLength,
        iterations: iterations,
        memoryKiB: memoryKiB,
      );
    } catch (_) {
      // Fall through to the pure-Dart path below.
    }
  }

  return _argon2DigestPureDart(
    password: password,
    secret: secret,
    salt: salt,
    iterations: iterations,
    memoryKiB: memoryKiB,
    parallelism: parallelism,
    hashLength: hashLength,
  );
}

Uint8List _argon2DigestPureDart({
  required String password,
  required String secret,
  required Uint8List salt,
  required int iterations,
  required int memoryKiB,
  required int parallelism,
  required int hashLength,
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
  final passwordBytes = _passwordAndSecretBytes(password, secret);

  final result = Uint8List(hashLength);
  argon.generateBytes(passwordBytes, result, 0, result.length);
  return result;
}

Uint8List _passwordAndSecretBytes(String password, String secret) {
  final p = utf8.encode(password);
  final s = utf8.encode(secret);
  final out = Uint8List(4 + p.length + 4 + s.length);
  final view = ByteData.sublistView(out);
  view.setUint32(0, p.length, Endian.big);
  out.setRange(4, 4 + p.length, p);
  view.setUint32(4 + p.length, s.length, Endian.big);
  out.setRange(8 + p.length, 8 + p.length + s.length, s);
  return out;
}
