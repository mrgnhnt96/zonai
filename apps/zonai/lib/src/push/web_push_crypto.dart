import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:jose/jose.dart';
import 'package:pointycastle/export.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// One browser's `PushSubscription.toJSON()`, as stored in a token column.
///
/// ```json
/// {"endpoint":"https://…","expirationTime":null,
///  "keys":{"p256dh":"<b64url>","auth":"<b64url>"}}
/// ```
class WebPushSubscription {
  const WebPushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  /// Parses a stored token, throwing a [FormatException] that says what is
  /// wrong with it.
  ///
  /// The endpoint must be `https`: it is a URL Zonai POSTs to on a client's
  /// say-so, and a push service is never reached any other way. Refusing
  /// anything else keeps a forged row from pointing the fan-out at an
  /// internal address.
  factory WebPushSubscription.parse(String token) {
    final Object? decoded;
    try {
      decoded = jsonDecode(token);
    } on FormatException {
      throw const FormatException(
        'not JSON — a web token must be the browser\'s '
        'PushSubscription.toJSON() stored as a JSON string',
      );
    }
    if (decoded is! Map) {
      throw const FormatException('not a JSON object');
    }

    final endpoint = switch (decoded['endpoint']) {
      final String value => Uri.tryParse(value),
      _ => null,
    };
    if (endpoint == null || endpoint.host.isEmpty) {
      throw const FormatException('missing or unreadable "endpoint"');
    }
    if (endpoint.scheme != 'https') {
      throw FormatException(
        'endpoint scheme is "${endpoint.scheme}"; push services are https',
      );
    }

    final keys = decoded['keys'];
    if (keys is! Map) throw const FormatException('missing "keys"');

    final p256dh = switch (keys['p256dh']) {
      final String value => decodeBase64Url(value),
      _ => null,
    };
    if (p256dh == null || p256dh.length != 65 || p256dh.first != 0x04) {
      throw const FormatException(
        'keys.p256dh is not a base64url uncompressed P-256 point',
      );
    }

    final auth = switch (keys['auth']) {
      final String value => decodeBase64Url(value),
      _ => null,
    };
    if (auth == null || auth.length != 16) {
      throw const FormatException('keys.auth is not 16 base64url bytes');
    }

    return WebPushSubscription(endpoint: endpoint, p256dh: p256dh, auth: auth);
  }

  final Uri endpoint;

  /// The browser's ECDH public key, 65 bytes.
  final Uint8List p256dh;

  /// The browser's 16-byte authentication secret.
  final Uint8List auth;
}

final _p256 = ECDomainParameters('prime256v1');

/// Encrypts [plaintext] for one subscription as a single `aes128gcm` record
/// (RFC 8188), keyed per RFC 8291.
///
/// [senderPrivate] and [salt] are fresh random values in production; they
/// are parameters only so RFC 8291's worked example can be replayed exactly.
Uint8List encryptWebPushPayload({
  required List<int> plaintext,
  required Uint8List p256dh,
  required Uint8List auth,
  BigInt? senderPrivate,
  Uint8List? salt,
}) {
  final asPrivate = senderPrivate ?? _randomScalar();
  final asPublic = _publicPointFor(asPrivate);
  final recordSalt = salt ?? _randomBytes(16);

  final uaPoint = _p256.curve.decodePoint(p256dh);
  final ecdhSecret = _bigIntToBytes(
    (ECDHBasicAgreement()..init(ECPrivateKey(asPrivate, _p256)))
        .calculateAgreement(ECPublicKey(uaPoint, _p256)),
    32,
  );

  final prkKey = _hmac(auth, ecdhSecret);
  final keyInfo = [...utf8.encode('WebPush: info'), 0, ...p256dh, ...asPublic];
  final ikm = _hmac(prkKey, [...keyInfo, 1]);

  final prk = _hmac(recordSalt, ikm);
  final cek = _hmac(prk, [
    ...utf8.encode('Content-Encoding: aes128gcm'),
    0,
    1,
  ]).sublist(0, 16);
  final nonce = _hmac(prk, [
    ...utf8.encode('Content-Encoding: nonce'),
    0,
    1,
  ]).sublist(0, 12);

  // One record, so it is also the last: the 0x02 delimiter, no padding.
  final padded = Uint8List.fromList([...plaintext, 2]);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(cek), 128, nonce, Uint8List(0)));
  final ciphertext = cipher.process(padded);

  final header = BytesBuilder()
    ..add(recordSalt)
    ..add(_uint32(webPushRecordSize))
    ..addByte(asPublic.length)
    ..add(asPublic);

  return (header..add(ciphertext)).toBytes();
}

/// The record size written into the `aes128gcm` header. A push service
/// accepts at most 4096 bytes of body, so one record always fits.
const webPushRecordSize = 4096;

/// The largest plaintext one record can carry: 4096 less the 86-byte header,
/// the 16-byte tag and the delimiter.
const maxWebPushPlaintextBytes = 4096 - 86 - 16 - 1;

/// The server's VAPID identity: the key pair and the subject.
///
/// Built once per config and checked on the way in — a private key that does
/// not match the public one the browsers subscribed with would otherwise
/// surface as a 403 from every push service, indistinguishable from a
/// subscription made under some other key.
class VapidSigner {
  VapidSigner._({
    required this.publicKey,
    required this.subject,
    required JsonWebKey key,
  }) : _key = key;

  /// Throws a [FormatException] naming what is wrong. Never echoes the
  /// private key: a log line carrying it is a leak.
  factory VapidSigner.fromKeys({
    required String publicKey,
    required String privateKey,
    required String subject,
  }) {
    final publicBytes = decodeBase64Url(publicKey);
    if (publicBytes == null ||
        publicBytes.length != 65 ||
        publicBytes.first != 0x04) {
      throw const FormatException(
        'the VAPID public key is not a base64url uncompressed P-256 point',
      );
    }

    final d = _privateScalar(privateKey);
    final derived = _publicPointFor(d);
    if (!_bytesEqual(derived, publicBytes)) {
      throw const FormatException(
        'the VAPID private key does not match the public key — every push '
        'service would answer 403',
      );
    }

    String b64(List<int> bytes) => encodeBase64Url(bytes);
    final key = JsonWebKey.fromJson({
      'kty': 'EC',
      'crv': 'P-256',
      'd': b64(_bigIntToBytes(d, 32)),
      'x': b64(publicBytes.sublist(1, 33)),
      'y': b64(publicBytes.sublist(33, 65)),
    });

    return VapidSigner._(
      publicKey: encodeBase64Url(publicBytes),
      subject: subject.trim(),
      key: key,
    );
  }

  /// Unpadded base64url, as the `k=` parameter wants it.
  final String publicKey;
  final String subject;
  final JsonWebKey _key;

  /// How long a minted JWT is valid. RFC 8292 caps it at 24 hours; half that
  /// leaves room for a push service whose clock runs ahead.
  static const lifetime = Duration(hours: 12);

  /// A cached token is replaced once less than this remains, so one never
  /// expires between being read here and arriving at the push service.
  static const _refreshMargin = Duration(hours: 1);

  final Map<String, ({String token, DateTime expires})> _tokens = {};

  /// The `Authorization` header value for a send to [endpoint].
  ///
  /// The JWT's `aud` is the endpoint's origin, so one token serves every
  /// subscription on the same push service and is cached per origin.
  String authorizationFor(Uri endpoint) =>
      'vapid t=${_tokenFor(endpoint.origin)}, k=$publicKey';

  String _tokenFor(String audience) {
    final now = clock.now();
    if (_tokens[audience] case (
      :final token,
      :final expires,
    ) when expires.difference(now) > _refreshMargin) {
      return token;
    }

    final expires = now.add(lifetime);
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'aud': audience,
        'exp': expires.millisecondsSinceEpoch ~/ 1000,
        'sub': subject,
      }
      ..setProtectedHeader('typ', 'JWT')
      ..addRecipient(_key, algorithm: 'ES256');
    final token = builder.build().toCompactSerialization();

    _tokens[audience] = (token: token, expires: expires);
    return token;
  }

  static BigInt _privateScalar(String privateKey) {
    final trimmed = privateKey.trim();
    if (trimmed.contains('-----BEGIN')) {
      final Map<String, dynamic> jwk;
      try {
        jwk = JsonWebKey.fromPem(trimmed).toJson();
      } catch (e) {
        // The exception's own message can echo the material it choked on.
        throw FormatException(
          'the VAPID private key is not a readable PEM key (${e.runtimeType})',
        );
      }
      if (jwk['kty'] != 'EC' || jwk['crv'] != 'P-256' || jwk['d'] == null) {
        throw const FormatException(
          'the VAPID private key is not an EC P-256 private key',
        );
      }
      return _bytesToBigInt(decodeBase64Url(jwk['d'] as String)!);
    }

    final raw = decodeBase64Url(trimmed);
    if (raw == null || raw.length != 32) {
      throw const FormatException(
        'the VAPID private key is neither PEM nor a 32-byte base64url scalar',
      );
    }
    final d = _bytesToBigInt(raw);
    if (d == BigInt.zero || d >= _p256.n) {
      throw const FormatException(
        'the VAPID private key is not a valid P-256 scalar',
      );
    }
    return d;
  }
}

/// See [WebPushConfig.decodeBase64Url].
Uint8List? decodeBase64Url(String value) =>
    WebPushConfig.decodeBase64Url(value);

String encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// The `Topic` header for a collapse key, or null when there is none.
///
/// RFC 8030 allows at most 32 characters from the base64url alphabet. A key
/// that already fits is sent as written, so it reads the same in a push
/// service's logs; anything else is hashed, which keeps "same key, same
/// topic" — the only property a replace needs.
String? webPushTopic(String? collapseKey) {
  if (collapseKey == null || collapseKey.isEmpty) return null;
  if (collapseKey.length <= 32 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(collapseKey)) {
    return collapseKey;
  }
  return encodeBase64Url(
    sha256.convert(utf8.encode(collapseKey)).bytes,
  ).substring(0, 32);
}

Uint8List _hmac(List<int> key, List<int> data) =>
    Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

Uint8List _publicPointFor(BigInt d) => (_p256.G * d)!.getEncoded(false);

final _random = Random.secure();

Uint8List _randomBytes(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) _random.nextInt(256)]);

BigInt _randomScalar() {
  while (true) {
    final d = _bytesToBigInt(_randomBytes(32));
    if (d > BigInt.zero && d < _p256.n) return d;
  }
}

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

Uint8List _uint32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
