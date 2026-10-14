import 'dart:io' show HttpClient, HttpDate;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:zonai/src/domain/photo_storage/photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/s3_signer.dart';
import 'package:zonai_schema/zonai_schema.dart' show ImageMimeType;

/// Photos as objects in an S3-compatible bucket (Cloudflare R2, MinIO, AWS).
///
/// Objects are addressed path-style, `<endpoint>/<bucket>/<key>`, and every
/// request is signed with SigV4 for [region]. Keys are the same relative
/// paths the disk backend uses, such as `posts/<id>.jpg`.
final class BucketPhotoStorage extends PhotoStorage {
  BucketPhotoStorage({
    required Uri endpoint,
    required this.bucket,
    required this.region,
    required this.credentials,
    http.Client? client,
  }) : _base = endpoint.toString().replaceFirst(RegExp(r'/+$'), ''),
       // A short idle timeout: a pooled connection keeps the process alive
       // until it expires, which a CLI run would otherwise sit through.
       _client =
           client ??
           IOClient(HttpClient()..idleTimeout = const Duration(seconds: 3));

  final String bucket;
  final String region;
  final S3Credentials credentials;

  final String _base;
  final http.Client _client;

  /// Uploads [bytes] to [key].
  ///
  /// The body is collected first: SigV4 signs a hash of the payload, and a
  /// photo is already capped by `PhotosConfig.maxBytes`, so holding it is
  /// cheaper than the chunked-signing protocol a streamed upload would need.
  @override
  Future<void> write(String key, Stream<List<int>> bytes) async {
    final builder = BytesBuilder(copy: false);
    await bytes.forEach(builder.add);
    final body = builder.takeBytes();

    final response = await _send(
      'PUT',
      key: key,
      body: body,
      headers: {
        'content-type':
            ImageMimeType.fromFileExtension(key.split('.').last)?.mimeType ??
            'application/octet-stream',
      },
    );
    await _expectOk(response, 'PUT', key);
  }

  @override
  Stream<List<int>> openRead(String key) async* {
    final response = await _send('GET', key: key);
    await _expectOk(response, 'GET', key);
    yield* response.stream;
  }

  @override
  Future<StoredPhoto?> stat(String key) async {
    final response = await _send('HEAD', key: key);
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return null;
    }
    await _expectOk(response, 'HEAD', key);
    await response.stream.drain<void>();

    final headers = response.headers;
    return StoredPhoto(
      key: key,
      size: int.parse(headers['content-length'] ?? '0'),
      modified: switch (headers['last-modified']) {
        final value? => HttpDate.parse(value),
        null => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      },
      etag: _unquote(headers['etag']),
    );
  }

  @override
  Future<bool> exists(String key) async => await stat(key) != null;

  @override
  Future<void> delete(String key) async {
    final response = await _send('DELETE', key: key);
    // S3 answers 204 whether or not the key existed; some compatible servers
    // answer 404 for a missing one, which is the same outcome here.
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return;
    }
    await _expectOk(response, 'DELETE', key);
    await response.stream.drain<void>();
  }

  /// Copies [from] to [to] inside the bucket, then deletes [from]. S3 has no
  /// rename.
  @override
  Future<void> rename(String from, String to) async {
    final response = await _send(
      'PUT',
      key: to,
      headers: {
        'x-amz-copy-source': '/$bucket/${s3Encode(from, keepSlash: true)}',
      },
    );
    await _expectOk(response, 'COPY', to);

    // A copy can fail after S3 has already sent 200, in which case the error
    // is in the body instead of the status.
    final body = await response.stream.bytesToString();
    if (body.contains('<Error>')) {
      throw BucketRequestException(
        operation: 'COPY',
        key: to,
        statusCode: response.statusCode,
        body: body,
      );
    }

    await delete(from);
  }

  /// Every object in the bucket, through `ListObjectsV2`, one page at a time.
  @override
  Stream<StoredPhoto> list() async* {
    String? continuation;
    do {
      final response = await _send(
        'GET',
        query: {'list-type': '2', 'continuation-token': ?continuation},
      );
      await _expectOk(response, 'LIST', '');
      final body = await response.stream.bytesToString();

      for (final match in _contents.allMatches(body)) {
        final entry = match.group(1)!;
        final key = _tag(entry, 'Key');
        final size = int.tryParse(_tag(entry, 'Size') ?? '');
        final modified = DateTime.tryParse(_tag(entry, 'LastModified') ?? '');
        // An entry this can't read is skipped, as the interface asks.
        if (key == null || size == null || modified == null) continue;

        yield StoredPhoto(
          key: key,
          size: size,
          modified: modified,
          etag: _unquote(_tag(entry, 'ETag')),
        );
      }

      continuation = _tag(body, 'IsTruncated') == 'true'
          ? _tag(body, 'NextContinuationToken')
          : null;
    } while (continuation != null);
  }

  Future<http.StreamedResponse> _send(
    String method, {
    String key = '',
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    Uint8List? body,
  }) {
    final queryString = [
      for (final MapEntry(:key, :value) in query.entries)
        '${s3Encode(key)}=${s3Encode(value)}',
    ].join('&');
    final uri = Uri.parse(
      '$_base/${s3Encode(bucket)}/${s3Encode(key, keepSlash: true)}'
      '${queryString.isEmpty ? '' : '?$queryString'}',
    );

    final request = http.Request(method, uri);
    if (body != null) request.bodyBytes = body;
    request.headers.addAll(
      signS3Request(
        method: method,
        uri: uri,
        payloadHash: body == null
            ? emptyPayloadHash
            : sha256.convert(body).toString(),
        credentials: credentials,
        region: region,
        now: clock.now(),
        headers: headers,
      )..remove('host'), // The client sets it from the URL, as signed.
    );
    return _client.send(request);
  }

  static Future<void> _expectOk(
    http.StreamedResponse response,
    String operation,
    String key,
  ) async {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    throw BucketRequestException(
      operation: operation,
      key: key,
      statusCode: response.statusCode,
      body: await response.stream.bytesToString().catchError((_) => ''),
    );
  }

  static final _contents = RegExp(r'<Contents>(.*?)</Contents>', dotAll: true);

  static String? _tag(String xml, String name) {
    final match = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    return match == null ? null : _unescapeXml(match.group(1)!);
  }

  static String? _unquote(String? etag) => etag?.replaceAll('"', '');

  static String _unescapeXml(String value) => value.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'),
    (match) => switch (match.group(1)!) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      final ref when ref.startsWith('#x') => String.fromCharCode(
        int.parse(ref.substring(2), radix: 16),
      ),
      final ref => String.fromCharCode(int.parse(ref.substring(1))),
    },
  );
}

/// A bucket request the server refused.
final class BucketRequestException implements Exception {
  const BucketRequestException({
    required this.operation,
    required this.key,
    required this.statusCode,
    required this.body,
  });

  final String operation;
  final String key;
  final int statusCode;

  /// The response body, S3's XML error document when it sent one.
  final String body;

  @override
  String toString() =>
      'BucketRequestException: $operation "$key" failed with $statusCode'
      '${body.isEmpty ? '' : ': $body'}';
}
