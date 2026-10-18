import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';

/// Why a webhook signature was refused.
enum WebhookSignatureFailure {
  /// The id, timestamp or signature header was absent.
  missingHeaders,

  /// The timestamp header was not a whole number of seconds.
  invalidTimestamp,

  /// The timestamp was further from now than the tolerance allows, in
  /// either direction — a replay of an old delivery, or a forged one.
  timestampOutOfTolerance,

  /// No `v1` signature in the header matched the body.
  noMatchingSignature,
}

/// Thrown by [WebhookSignature.verify] when a delivery does not check out.
class WebhookSignatureException implements Exception {
  const WebhookSignatureException(this.failure);

  final WebhookSignatureFailure failure;

  @override
  String toString() => 'WebhookSignatureException: ${failure.name}';
}

/// Verifies webhooks signed the Svix way, which is also the
/// [Standard Webhooks](https://www.standardwebhooks.com) scheme — Resend,
/// Clerk and Svix itself all send these.
///
/// The sender signs `"$id.$timestamp.$body"` with HMAC-SHA256, keyed by the
/// base64 part of a `whsec_…` secret, and sends the result as
/// `v1,<base64>` in a space-separated signature header (several during a
/// secret rotation). The headers are `svix-id`, `svix-timestamp` and
/// `svix-signature`, or the `webhook-*` names; either set is read.
///
/// ```dart
/// final signature = WebhookSignature(
///   Platform.environment['RESEND_WEBHOOK_SECRET']!,
/// );
///
/// if (!signature.isValid(bodyBytes, headers)) {
///   // answer 401
/// }
/// ```
///
/// Verify against the body bytes exactly as received: re-encoding a decoded
/// JSON body changes its bytes and the signature no longer matches.
class WebhookSignature {
  /// [secret] is the signing secret as the provider shows it. A `whsec_`
  /// prefix is stripped before the remainder is base64-decoded.
  WebhookSignature(String secret, {this.tolerance = const Duration(minutes: 5)})
    : _key = base64.decode(
        secret.startsWith(_secretPrefix)
            ? secret.substring(_secretPrefix.length)
            : secret,
      );

  static const _secretPrefix = 'whsec_';

  /// How far a delivery's timestamp may sit from now, either way.
  final Duration tolerance;

  final List<int> _key;

  /// Whether [body] and [headers] carry a valid, fresh signature.
  bool isValid(List<int> body, Map<String, String> headers) =>
      check(body, headers) == null;

  /// Throws [WebhookSignatureException] unless [body] and [headers] carry a
  /// valid, fresh signature.
  void verify(List<int> body, Map<String, String> headers) {
    if (check(body, headers) case final failure?) {
      throw WebhookSignatureException(failure);
    }
  }

  /// Why [body] and [headers] fail verification, or `null` when they pass.
  ///
  /// Header names are matched case-insensitively.
  WebhookSignatureFailure? check(List<int> body, Map<String, String> headers) {
    final lower = {
      for (final MapEntry(:key, :value) in headers.entries)
        key.toLowerCase(): value,
    };
    String? header(String name) =>
        lower['svix-$name'] ?? lower['webhook-$name'];

    final (id, timestamp, signatures) = (
      header('id'),
      header('timestamp'),
      header('signature'),
    );
    if (id == null || timestamp == null || signatures == null) {
      return WebhookSignatureFailure.missingHeaders;
    }

    final seconds = int.tryParse(timestamp.trim());
    if (seconds == null) {
      return WebhookSignatureFailure.invalidTimestamp;
    }

    // Compared as bounds around now, never as a difference or a DateTime: a
    // sender controls the value, and an extreme one would overflow the
    // subtraction or throw out of the DateTime constructor.
    final now = clock.now().millisecondsSinceEpoch ~/ 1000;
    if (seconds < now - tolerance.inSeconds ||
        seconds > now + tolerance.inSeconds) {
      return WebhookSignatureFailure.timestampOutOfTolerance;
    }

    final expected = _sign(id, timestamp.trim(), body);
    for (final entry in signatures.split(' ')) {
      if (entry.split(',') case ['v1', final candidate]) {
        final List<int> bytes;
        try {
          bytes = base64.decode(candidate);
        } on FormatException {
          continue;
        }
        if (_constantTimeEquals(bytes, expected)) return null;
      }
    }

    return WebhookSignatureFailure.noMatchingSignature;
  }

  /// The `v1,<base64>` signature header value for a delivery — what a sender
  /// would put in `svix-signature`. Useful for tests and for signing
  /// outgoing webhooks.
  String sign(String id, DateTime timestamp, List<int> body) {
    final seconds = timestamp.millisecondsSinceEpoch ~/ 1000;
    return 'v1,${base64.encode(_sign(id, '$seconds', body))}';
  }

  List<int> _sign(String id, String timestamp, List<int> body) {
    final hmac = Hmac(sha256, _key);
    return hmac.convert([...utf8.encode('$id.$timestamp.'), ...body]).bytes;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
