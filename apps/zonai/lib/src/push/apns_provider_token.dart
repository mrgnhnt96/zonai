import 'package:clock/clock.dart';
import 'package:jose/jose.dart';
import 'package:zonai/src/push/push_courier.dart';

/// Mints and caches the ES256 provider token APNs authenticates with.
///
/// Cheaper than FCM's equivalent — there is no round trip, because Apple has
/// no token endpoint. You sign a JWT with the `.p8` and send it as a bearer.
/// Which makes the caching here about **Apple's rules** rather than about
/// cost:
///
///   * a provider token older than **one hour** is rejected, and
///   * regenerating one *more often than every 20 minutes* is itself refused,
///     with `TooManyProviderTokenUpdates`.
///
/// So this is a window rather than a deadline, and a naive "sign one per
/// send" implementation is not merely wasteful — it is rejected outright once
/// a fan-out exceeds a handful of recipients. That failure looks like an auth
/// problem and sends you to check the key, which is fine.
class ApnsProviderToken {
  ApnsProviderToken({
    required this.privateKeyPem,
    required this.keyId,
    required this.teamId,
  });

  /// The PEM-encoded P-256 private key from the `.p8`.
  ///
  /// Never logged and never placed in an error message: a stack trace
  /// carrying a private key is a leak that outlives the incident.
  final String privateKeyPem;

  final String keyId;
  final String teamId;

  /// Comfortably inside Apple's one-hour ceiling and outside its twenty-minute
  /// floor. Sitting in the middle of the two is the only safe place: closer to
  /// the ceiling risks a token expiring mid-batch, closer to the floor risks
  /// `TooManyProviderTokenUpdates` on a busy queue.
  static const refreshAfter = Duration(minutes: 40);

  String? _token;
  DateTime? _mintedAt;

  String get() {
    if (_token case final token? when _isFresh) return token;
    return _mint();
  }

  bool get _isFresh {
    final mintedAt = _mintedAt;
    if (mintedAt == null) return false;
    return clock.now().difference(mintedAt) < refreshAfter;
  }

  String _mint() {
    final JsonWebKey key;
    try {
      key = JsonWebKey.fromPem(privateKeyPem);
    } catch (e) {
      // Deliberately excludes the exception's own message, which can echo the
      // material it choked on.
      throw PushTransportException(
        'APNs auth key is not a readable PEM key (${e.runtimeType}). It '
        'should be the .p8 downloaded from Apple, unmodified.',
      );
    }

    final now = clock.now();
    final issued = now.millisecondsSinceEpoch ~/ 1000;

    // No `exp`: Apple defines the lifetime itself and rejects a token that
    // carries one. The `kid` header is how it knows which key to verify
    // with — the `.p8` does not carry its own id.
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {'iss': teamId, 'iat': issued}
      ..setProtectedHeader('typ', 'JWT')
      ..setProtectedHeader('kid', keyId)
      ..addRecipient(key, algorithm: 'ES256');

    final String token;
    try {
      token = builder.build().toCompactSerialization();
    } on TypeError catch (e) {
      // `JsonWebKey.fromPem` happily parses an RSA key, and the mismatch only
      // surfaces here, as a cast error naming two classes an app author has
      // no reason to have heard of. Pointing `ApnsConfig.credentials` at an
      // FCM service-account key is an easy mistake — both are PEM, both are
      // "the push key" — so it is worth saying which one is which.
      throw PushTransportException(
        'APNs auth key is not an EC P-256 key, so it cannot sign the ES256 '
        'token Apple requires. An FCM service-account key (RSA) is the usual '
        'mix-up; the APNs key is the .p8 from Apple. ($e)',
      );
    }

    _token = token;
    _mintedAt = now;
    return token;
  }
}
