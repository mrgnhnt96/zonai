import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  group('SignUpAuthBody.fromJson', () {
    test('defaults table to users when omitted', () {
      // A bare body used to cast null->String here, which the route surfaced
      // as HTTP 500 rather than reaching the handler.
      final body = SignUpAuthBody.fromJson({
        'email': 'a@b.c',
        'password': 'hunter2',
        'object': {'name': 'A'},
      });

      expect(body.table, 'users');
      expect(body.email, 'a@b.c');
      expect(body.password, 'hunter2');
      expect(body.object, {'name': 'A'});
    });

    test('defaults table to users when empty', () {
      final body = SignUpAuthBody.fromJson({
        'table': '',
        'email': 'a@b.c',
        'password': 'hunter2',
      });

      expect(body.table, 'users');
      expect(body.object, isNull);
    });

    test('keeps an explicit table', () {
      final body = SignUpAuthBody.fromJson({
        'table': 'admins',
        'email': 'a@b.c',
        'password': 'hunter2',
      });

      expect(body.table, 'admins');
    });

    test('throws ArgumentError, not a cast error, without email or password', () {
      expect(
        () => SignUpAuthBody.fromJson({'table': 'users'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SignUpAuthBody.fromJson({'email': 'a@b.c'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when object is not a map', () {
      expect(
        () => SignUpAuthBody.fromJson({
          'email': 'a@b.c',
          'password': 'hunter2',
          'object': 'not-a-map',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('round-trips through toJson', () {
      final original = SignUpAuthBody(
        table: 'users',
        email: 'a@b.c',
        password: 'hunter2',
        object: const {'name': 'A'},
      );

      final restored = SignUpAuthBody.fromJson(original.toJson());

      expect(restored.table, original.table);
      expect(restored.email, original.email);
      expect(restored.password, original.password);
      expect(restored.object, original.object);
    });
  });

  group('AdminAuthBody.fromJson', () {
    test('parses an admin sign-in body', () {
      final body = AdminAuthBody.fromJson({
        'type': 'adminSignIn',
        'email': 'a@b.c',
        'password': 'hunter2',
      });

      expect(body, isA<AdminSignInAuthBody>());
    });

    test('throws ArgumentError, not a cast error, when type is missing', () {
      expect(
        () => AdminAuthBody.fromJson({'email': 'a@b.c', 'password': 'x'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
