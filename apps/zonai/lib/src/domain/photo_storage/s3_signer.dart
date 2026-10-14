import 'dart:convert';

import 'package:crypto/crypto.dart';

/// An S3 key pair, as read from the server's environment.
final class S3Credentials {
  const S3Credentials({
    required this.accessKeyId,
    required this.secretAccessKey,
  });

  final String accessKeyId;
  final String secretAccessKey;
}

/// The SHA-256 of an empty body, which every request without one signs.
final emptyPayloadHash = sha256.convert(const []).toString();

/// Signs an S3 request with AWS Signature Version 4.
///
/// Returns [headers] plus `host`, `x-amz-date`, `x-amz-content-sha256` and
/// `authorization`, every one of them signed. [uri]'s path must already be
/// percent-encoded the way [s3Encode] encodes it, since S3 signs the path as
/// sent rather than decoding it first; its query is re-encoded here.
///
/// The steps and the names follow
/// https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html.
Map<String, String> signS3Request({
  required String method,
  required Uri uri,
  required String payloadHash,
  required S3Credentials credentials,
  required String region,
  required DateTime now,
  Map<String, String> headers = const {},
}) {
  final utc = now.toUtc();
  final amzDate = _amzDate(utc);
  final date = amzDate.substring(0, 8);
  const service = 's3';

  final signed = <String, String>{
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): value.trim(),
    'host': uri.hasPort && uri.port != _defaultPort(uri.scheme)
        ? '${uri.host}:${uri.port}'
        : uri.host,
    'x-amz-date': amzDate,
    'x-amz-content-sha256': payloadHash,
  };
  final names = signed.keys.toList()..sort();

  final query = [
    for (final MapEntry(:key, :value) in uri.queryParameters.entries)
      '${s3Encode(key)}=${s3Encode(value)}',
  ]..sort();

  final canonicalRequest = [
    method,
    uri.path.isEmpty ? '/' : uri.path,
    query.join('&'),
    for (final name in names) '$name:${signed[name]}',
    '',
    names.join(';'),
    payloadHash,
  ].join('\n');

  final scope = '$date/$region/$service/aws4_request';
  final stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  List<int> hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  final signingKey = [
    date,
    region,
    service,
    'aws4_request',
  ].fold(utf8.encode('AWS4${credentials.secretAccessKey}'), hmac);
  final signature = Hmac(
    sha256,
    signingKey,
  ).convert(utf8.encode(stringToSign)).toString();

  return {
    ...signed,
    'authorization':
        'AWS4-HMAC-SHA256 '
        'Credential=${credentials.accessKeyId}/$scope,'
        'SignedHeaders=${names.join(';')},'
        'Signature=$signature',
  };
}

/// Percent-encodes [value] as SigV4 requires: everything but `A-Z a-z 0-9
/// - _ . ~` is escaped, with uppercase hex. With [keepSlash], `/` is kept, for
/// an object key used as a path.
String s3Encode(String value, {bool keepSlash = false}) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final unreserved =
        (byte >= 0x41 && byte <= 0x5a) || // A-Z
        (byte >= 0x61 && byte <= 0x7a) || // a-z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        byte == 0x2d || // -
        byte == 0x5f || // _
        byte == 0x2e || // .
        byte == 0x7e || // ~
        (keepSlash && byte == 0x2f);
    if (unreserved) {
      out.writeCharCode(byte);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

String _amzDate(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;
