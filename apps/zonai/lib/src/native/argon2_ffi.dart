import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// Signature verified against the real libsodium 1.0.21 header
// (crypto_pwhash.h):
//
//   int crypto_pwhash(unsigned char * const out, unsigned long long outlen,
//                     const char * const passwd, unsigned long long passwdlen,
//                     const unsigned char * const salt,
//                     unsigned long long opslimit, size_t memlimit, int alg);
//
// `alg` value for Argon2id (crypto_pwhash_ALG_ARGON2ID13, from
// crypto_pwhash_argon2id.h). This is the same algorithm as
// `package:argon2`'s `Argon2Parameters.ARGON2_id`.
const _algArgon2id13 = 2;

typedef _CryptoPwhashNative =
    Int32 Function(
      Pointer<Uint8> out,
      Uint64 outlen,
      Pointer<Uint8> passwd,
      Uint64 passwdlen,
      Pointer<Uint8> salt,
      Uint64 opslimit,
      Uint64 memlimit,
      Int32 alg,
    );
typedef _CryptoPwhashDart =
    int Function(
      Pointer<Uint8> out,
      int outlen,
      Pointer<Uint8> passwd,
      int passwdlen,
      Pointer<Uint8> salt,
      int opslimit,
      int memlimit,
      int alg,
    );

typedef _SodiumInitNative = Int32 Function();
typedef _SodiumInitDart = int Function();

DynamicLibrary? _library;
_CryptoPwhashDart? _cryptoPwhash;

/// Platform-specific shared library file name for the vendored libsodium
/// build used for native Argon2id hashing.
String get defaultLibraryFileName => switch (Platform.operatingSystem) {
  'macos' => 'libargon2sodium.dylib',
  'linux' => 'libargon2sodium.so',
  'windows' => 'argon2sodium.dll',
  _ => throw UnsupportedError(
    'Unsupported platform for native Argon2: ${Platform.operatingSystem}',
  ),
};

/// Whether [install] has been called successfully.
bool get isInstalled => _library != null;

/// Loads the native Argon2 (libsodium) library from [path] and calls
/// `sodium_init()`, which libsodium requires before any other call.
///
/// Must be called once before [cryptoPwhashArgon2id].
void install(String path) {
  if (_library != null) return;

  final library = DynamicLibrary.open(File(path).absolute.path);

  final sodiumInit = library.lookupFunction<_SodiumInitNative, _SodiumInitDart>(
    'sodium_init',
  );
  // 0 == first-time success, 1 == already initialized. Both are fine;
  // only a negative return indicates a real failure.
  if (sodiumInit() < 0) {
    throw StateError('sodium_init() failed');
  }

  _cryptoPwhash = library
      .lookupFunction<_CryptoPwhashNative, _CryptoPwhashDart>('crypto_pwhash');
  _library = library;
}

/// Raw Argon2id key derivation via libsodium's `crypto_pwhash`, matching
/// `package:argon2`'s `Argon2Parameters.ARGON2_id` output for the same
/// inputs -- same standardized algorithm, just compiled native code
/// instead of pure Dart (see hash_password.dart for why that matters).
///
/// [memoryKiB] is converted to bytes (libsodium's `memlimit` is in bytes,
/// zonai's cost parameter is in KiB). [password] is whatever bytes the
/// caller wants hashed -- callers needing a secret/pepper mixed in must
/// pre-combine it into [password] themselves, matching how
/// `package:argon2` is used elsewhere in this codebase.
Uint8List cryptoPwhashArgon2id({
  required List<int> password,
  required Uint8List salt,
  required int outLen,
  required int iterations,
  required int memoryKiB,
}) {
  final cryptoPwhash = _cryptoPwhash;
  if (cryptoPwhash == null) {
    throw StateError(
      'Native Argon2 library not installed; call install() first',
    );
  }

  return using((arena) {
    final passwordBytes = Uint8List.fromList(password);
    final passwordPtr = arena<Uint8>(passwordBytes.length);
    passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);

    final saltPtr = arena<Uint8>(salt.length);
    saltPtr.asTypedList(salt.length).setAll(0, salt);

    final outPtr = arena<Uint8>(outLen);

    final rc = cryptoPwhash(
      outPtr,
      outLen,
      passwordPtr,
      passwordBytes.length,
      saltPtr,
      iterations,
      memoryKiB * 1024,
      _algArgon2id13,
    );

    if (rc != 0) {
      throw StateError(
        'crypto_pwhash failed (rc=$rc) -- likely out of memory for the '
        'requested memoryKiB=$memoryKiB',
      );
    }

    return Uint8List.fromList(outPtr.asTypedList(outLen));
  });
}
