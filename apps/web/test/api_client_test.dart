import 'package:test/test.dart';
import 'package:zonai_web/api/api_client.dart';

void main() {
  group('isUnauthorizedStatusCode', () {
    test('treats 401 and 403 as unauthorized', () {
      expect(isUnauthorizedStatusCode(401), isTrue);
      expect(isUnauthorizedStatusCode(403), isTrue);
    });

    test('ignores other status codes', () {
      expect(isUnauthorizedStatusCode(200), isFalse);
      expect(isUnauthorizedStatusCode(404), isFalse);
      expect(isUnauthorizedStatusCode(500), isFalse);
    });
  });
}
