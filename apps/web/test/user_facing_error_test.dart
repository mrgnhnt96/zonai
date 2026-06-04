import 'package:test/test.dart';
import 'package:zonai_web/utils/user_facing_error.dart';

void main() {
  group('userFacingError', () {
    test('unwraps failed update wrapper and radix parse hint', () {
      expect(
        userFacingError(
          StateError(
            'Failed to update row: FormatException: Invalid radix-10 number\n'
            'test-1779400790199_co\n^',
          ),
        ),
        'An ID field has an invalid format. Use the full text ID (for example test-1234567890_co).',
      );
    });

    test('maps foreign key failures to a clear message', () {
      expect(
        userFacingError(
          StateError('Failed to update row: SqliteException(787): FOREIGN KEY constraint failed'),
        ),
        'That reference does not match an existing row (for example, the company may not exist).',
      );
    });
  });
}
