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
    group('a full disk', () {
      test('is recognised as SQLITE_FULL rather than the failing operation', () {
        final mapped = mapDatabaseError(
          StateError('SqliteException(13): database or disk is full'),
          table: '_log',
        );

        expect(mapped, isA<DiskFullException>());
      });

      test('is recognised from the errno underneath it', () {
        final mapped = mapDatabaseError(
          StateError('FileSystemException: No space left on device, errno = 28'),
          table: '_log',
        );

        expect(mapped, isA<DiskFullException>());
      });

      test('is recognised from SQLITE_IOERR_WRITE, which is what a full WAL '
          'usually looks like', () {
        final mapped = mapDatabaseError(
          StateError('SqliteException(778): disk I/O error'),
          table: '_log',
        );

        expect(mapped, isA<DiskFullException>());
      });

      test('wins over the constraint cases, which a write failure can also '
          'mention', () {
        // Ordering matters: were this checked after the constraint branches,
        // a disk-full error whose message also mentioned a key would be
        // reported as a constraint violation and send the operator hunting
        // for a data problem that does not exist.
        final mapped = mapDatabaseError(
          StateError('database or disk is full (foreign key)'),
          table: '_log',
        );

        expect(mapped, isA<DiskFullException>());
      });

      test('says what to do, since the database cannot reclaim space itself', () {
        final mapped = mapDatabaseError(
          StateError('SqliteException(13): database or disk is full'),
          table: '_log',
        );

        expect(
          mapped.toString(),
          allOf(
            contains('Extend the volume'),
            contains('requires a write'),
          ),
          reason:
              'at zero bytes free every recovery path zonai has needs the '
              'write that is being refused, so the message has to name the '
              'one action that works',
        );
      });

      test('passes through unchanged when mapped a second time', () {
        const error = DiskFullException();
        expect(mapDatabaseError(error, table: '_log'), same(error));
      });
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

    // A full volume surfaces as a write failure on whatever statement was
    // unlucky enough to be running. Reported from a live deployment that sat
    // at 100% for thirteen days with a green health check: the process is up,
    // so liveness says nothing about whether writes work.
  });
}
