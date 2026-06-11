import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

void main() {
  group('mapDatabaseError', () {
    test('passes through typed exceptions', () {
      const error = ColumnNotFoundException(
        table: 'users',
        columnName: 'email',
      );
      expect(mapDatabaseError(error, table: 'users'), same(error));
    });

    test('maps foreign key constraint failures', () {
      final mapped = mapDatabaseError(
        StateError(
          'SqliteException(787): FOREIGN KEY constraint failed',
        ),
        table: 'posts',
      );

      expect(mapped, isA<ForeignKeyConstraintException>());
      expect(
        mapped.toString(),
        'That reference does not match an existing row.',
      );
    });

    test('maps unique constraint failures', () {
      final mapped = mapDatabaseError(
        StateError('UNIQUE constraint failed: users.email'),
        table: 'users',
      );

      expect(mapped, isA<UniqueConstraintException>());
    });

    test('maps invalid id format failures', () {
      final mapped = mapDatabaseError(
        FormatException('Invalid radix-10 number'),
        table: 'users',
      );

      expect(mapped, isA<InvalidColumnValueException>());
    });

    test('parses schema exceptions from worker strings', () {
      final mapped = mapDatabaseError(
        'Error handling request: Table "missing" is not registered',
        table: 'missing',
      );

      expect(mapped, isA<TableNotRegisteredException>());
    });
  });

  group('mapWorkerError', () {
    test('maps worker failures using request table context', () {
      final mapped = mapWorkerError(
        MessageHandlerFailedException(
          'Error handling request',
          cause: 'Column "company_id" not found on table "users"',
        ),
        table: 'users',
      );

      expect(mapped, isA<ColumnNotFoundException>());
    });
  });
}
