import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The credential half of an API token: generating one, recognising one, and
/// reducing one to what the database is allowed to keep.
///
/// The plaintext exists exactly twice -- once in the process that generated
/// it, and once wherever the person who ran that command pasted it. Nothing
/// here can recover it from a stored row, which is the property that makes
/// "shown once, at creation" a fact rather than a promise.
abstract final class ApiTokenSecret {
  /// Marks the string as a zonai API token, and does two jobs.
  ///
  /// It is a **format discriminator**: the bearer value is tested against it
  /// before anything tries to parse it, so an API token is never fed to the
  /// JWT verifier and a JWT is never looked up as a token. Neither has to
  /// guess what the other is.
  ///
  /// It is also a **secret-scanner anchor**. A fixed, greppable prefix is what
  /// lets GitHub push protection, `gitleaks` and a log-redaction filter
  /// recognise the thing at all -- the reason Stripe, GitHub and Slack all
  /// prefix theirs.
  static const prefix = 'zonai_pat_';

  /// Bytes of CSPRNG output behind the prefix. 256 bits: enough that the
  /// stored SHA-256 has nothing to brute-force, which is what lets the hash
  /// be SHA-256 rather than something memory-hard that would be paid for on
  /// every request.
  static const entropyBytes = 32;

  /// How much of the plaintext is kept in the clear, on the row, so a human
  /// can match a token in a log line to the row it came from. Long enough to
  /// be unambiguous in a list, far too short to be guessable.
  static const displayLength = prefix.length + 8;

  /// A fresh credential. The only place a plaintext token is ever produced.
  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(entropyBytes, (_) => random.nextInt(256));
    return '$prefix${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  /// What `_api_tokens.token_hash` stores.
  ///
  /// SHA-256, not Argon2, and deliberately: the input is [entropyBytes] of
  /// CSPRNG output, so there is no dictionary to run against it and a
  /// memory-hard hash would buy nothing while costing something on every
  /// authenticated request. That reasoning does not transfer to `$.password`,
  /// whose input a human chose.
  static String hash(String plaintext) =>
      sha256.convert(utf8.encode(plaintext)).toString();

  /// Whether [value] is shaped like an API token, and so must be resolved as
  /// one rather than verified as a JWT.
  ///
  /// Shape only. A string that passes here can still be unknown, revoked or
  /// expired -- the row decides that, and this only decides which door the
  /// value goes through.
  static bool looksLike(String value) => normalize(value).startsWith(prefix);

  /// Strips an `Authorization`-header `Bearer ` wrapper and surrounding
  /// whitespace, so the same string is tested, hashed and stored no matter
  /// which layer it arrived through.
  static String normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return trimmed.substring(7).trim();
    }
    return trimmed;
  }

  /// The prefix stored on the row for display. Never enough to authenticate.
  static String displayPrefix(String plaintext) {
    final normalized = normalize(plaintext);
    if (normalized.length <= displayLength) return normalized;
    return normalized.substring(0, displayLength);
  }
}
