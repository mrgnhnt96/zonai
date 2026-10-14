import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:zonai/src/domain/photo_storage/s3_signer.dart';

/// An in-process stand-in for an S3-compatible bucket, so storage can be
/// tested without a cloud account or a MinIO container.
///
/// It answers the requests `BucketPhotoStorage` makes (PUT, copy, GET, HEAD,
/// DELETE and `ListObjectsV2`) path-style for one [bucket], and refuses with
/// 403 any request whose SigV4 signature or payload hash doesn't match what
/// [credentials] would produce — so a test passing here means the requests
/// were signed as they were sent.
final class FakeS3Server {
  FakeS3Server._(this._server, {required this.bucket, required this.pageSize}) {
    _server.listen(_handle);
  }

  static Future<FakeS3Server> start({
    String bucket = 'photos',
    int pageSize = 1000,
  }) async => FakeS3Server._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    bucket: bucket,
    pageSize: pageSize,
  );

  static const credentials = S3Credentials(
    accessKeyId: 'test-access-key',
    secretAccessKey: 'test-secret-key',
  );

  static const region = 'auto';

  final HttpServer _server;
  final String bucket;

  /// Most keys one `ListObjectsV2` page returns, to exercise pagination.
  final int pageSize;

  /// Stored objects by key.
  final objects =
      <String, ({Uint8List bytes, String contentType, DateTime modified})>{};

  /// Every request as `METHOD path`, in the order they arrived.
  final requests = <String>[];

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await request.fold(BytesBuilder(copy: false), (b, chunk) {
      b.add(chunk);
      return b;
    });
    final bytes = body.takeBytes();
    final response = request.response;
    requests.add('${request.method} ${request.uri}');

    try {
      if (!_signedCorrectly(request, bytes)) {
        return _error(response, 403, 'SignatureDoesNotMatch');
      }

      final segments = request.uri.pathSegments;
      if (segments.isEmpty || segments.first != bucket) {
        return _error(response, 404, 'NoSuchBucket');
      }
      final key = segments.skip(1).join('/');

      switch (request.method) {
        case 'GET' when key.isEmpty:
          return _list(request, response);
        case 'PUT':
          final source = request.headers.value('x-amz-copy-source');
          if (source != null) {
            final from = Uri.decodeComponent(
              source.substring('/$bucket/'.length),
            );
            final object = objects[from];
            // A real copy can fail after the 200 is sent; mirror that.
            if (object == null) {
              response.statusCode = 200;
              response.write('<Error><Code>NoSuchKey</Code></Error>');
              return;
            }
            objects[key] = (
              bytes: object.bytes,
              contentType: object.contentType,
              modified: DateTime.now().toUtc(),
            );
            response.write('<CopyObjectResult></CopyObjectResult>');
            return;
          }
          objects[key] = (
            bytes: bytes,
            contentType:
                request.headers.contentType?.mimeType ??
                'application/octet-stream',
            modified: DateTime.now().toUtc(),
          );
          response.headers.set('etag', _etag(bytes));
          return;
        case 'GET' || 'HEAD':
          final object = objects[key];
          if (object == null) return _error(response, 404, 'NoSuchKey');
          response.headers
            ..contentType = ContentType.parse(object.contentType)
            ..contentLength = object.bytes.length
            ..set('etag', _etag(object.bytes))
            ..set('last-modified', HttpDate.format(object.modified));
          if (request.method == 'GET') response.add(object.bytes);
          return;
        case 'DELETE':
          objects.remove(key);
          response.statusCode = 204;
          return;
      }
      return _error(response, 405, 'MethodNotAllowed');
    } finally {
      await response.close();
    }
  }

  void _list(HttpRequest request, HttpResponse response) {
    final keys = objects.keys.toList()..sort();
    final start = switch (request.uri.queryParameters['continuation-token']) {
      final token? => int.parse(token),
      null => 0,
    };
    final page = keys.skip(start).take(pageSize).toList();
    final truncated = start + page.length < keys.length;

    final xml = StringBuffer('<ListBucketResult>');
    for (final key in page) {
      final object = objects[key]!;
      xml.write(
        '<Contents><Key>${_escape(key)}</Key>'
        '<LastModified>${object.modified.toIso8601String()}</LastModified>'
        '<ETag>${_escape(_etag(object.bytes))}</ETag>'
        '<Size>${object.bytes.length}</Size></Contents>',
      );
    }
    xml.write('<IsTruncated>$truncated</IsTruncated>');
    if (truncated) {
      xml.write(
        '<NextContinuationToken>${start + page.length}</NextContinuationToken>',
      );
    }
    xml.write('</ListBucketResult>');
    response.write(xml);
  }

  bool _signedCorrectly(HttpRequest request, List<int> body) {
    final authorization = request.headers.value('authorization');
    final amzDate = request.headers.value('x-amz-date');
    final payloadHash = request.headers.value('x-amz-content-sha256');
    if (authorization == null || amzDate == null || payloadHash == null) {
      return false;
    }
    if (payloadHash != sha256.convert(body).toString()) return false;

    final signedNames = RegExp(
      r'SignedHeaders=([^,]+)',
    ).firstMatch(authorization)!.group(1)!.split(';');
    const added = {'host', 'x-amz-date', 'x-amz-content-sha256'};
    final now = DateTime.parse(
      '${amzDate.substring(0, 8)}T${amzDate.substring(9)}',
    );

    final expected = signS3Request(
      method: request.method,
      uri: request.requestedUri,
      payloadHash: payloadHash,
      credentials: credentials,
      region: region,
      now: now,
      headers: {
        for (final name in signedNames)
          if (!added.contains(name)) name: request.headers.value(name) ?? '',
      },
    );
    return expected['authorization'] == authorization;
  }

  static String _etag(List<int> bytes) => '"${md5.convert(bytes)}"';

  static String _escape(String value) => const HtmlEscape().convert(value);

  static void _error(HttpResponse response, int status, String code) {
    response
      ..statusCode = status
      ..write('<Error><Code>$code</Code></Error>');
  }
}
