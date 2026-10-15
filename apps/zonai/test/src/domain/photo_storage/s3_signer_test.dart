import 'package:test/test.dart';
import 'package:zonai/src/domain/photo_storage/s3_signer.dart';

void main() {
  group(signS3Request, () {
    // The "GET Object" example from AWS's SigV4 header-signing docs:
    // https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
    test('matches the AWS documentation example', () {
      final headers = signS3Request(
        method: 'GET',
        uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
        payloadHash: emptyPayloadHash,
        credentials: const S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        ),
        region: 'us-east-1',
        now: DateTime.utc(2013, 5, 24),
        headers: {'Range': 'bytes=0-9'},
      );

      expect(
        headers['authorization'],
        'AWS4-HMAC-SHA256 '
        'Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,'
        'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,'
        'Signature='
        'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      );
      expect(headers['x-amz-date'], '20130524T000000Z');
      expect(headers['host'], 'examplebucket.s3.amazonaws.com');
    });

    test('signs a non-default port as part of the host', () {
      final headers = signS3Request(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:9000/photos/a.jpg'),
        payloadHash: emptyPayloadHash,
        credentials: const S3Credentials(
          accessKeyId: 'a',
          secretAccessKey: 'b',
        ),
        region: 'auto',
        now: DateTime.utc(2026),
      );

      expect(headers['host'], '127.0.0.1:9000');
    });
  });

  group(presignS3Url, () {
    // The example from AWS's query-string (presigned URL) docs:
    // https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
    test('matches the AWS documentation example', () {
      final url = presignS3Url(
        uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
        credentials: const S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        ),
        region: 'us-east-1',
        now: DateTime.utc(2013, 5, 24),
        expires: const Duration(hours: 24),
      );

      expect(
        url.toString(),
        'https://examplebucket.s3.amazonaws.com/test.txt'
        '?X-Amz-Algorithm=AWS4-HMAC-SHA256'
        '&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3'
        '%2Faws4_request'
        '&X-Amz-Date=20130524T000000Z'
        '&X-Amz-Expires=86400'
        '&X-Amz-SignedHeaders=host'
        '&X-Amz-Signature='
        'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
      );
    });

    test('keeps a non-default port in the URL and the signed host', () {
      final url = presignS3Url(
        uri: Uri.parse('http://127.0.0.1:9000/photos/a%20b.jpg'),
        credentials: const S3Credentials(
          accessKeyId: 'a',
          secretAccessKey: 'b',
        ),
        region: 'auto',
        now: DateTime.utc(2026),
        expires: const Duration(minutes: 5),
      );

      expect(url.port, 9000);
      expect(url.path, '/photos/a%20b.jpg');
      expect(url.queryParameters['X-Amz-Expires'], '300');
    });
  });

  group(s3Encode, () {
    test('leaves only unreserved characters', () {
      expect(s3Encode('a-z_A.Z~0 9+/=&é'), 'a-z_A.Z~0%209%2B%2F%3D%26%C3%A9');
    });

    test('keeps slashes in a key path', () {
      expect(s3Encode('posts/a b.jpg', keepSlash: true), 'posts/a%20b.jpg');
    });
  });
}
