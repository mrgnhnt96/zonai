import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';

import '../routes/components/exception_catcher.dart';

/// Error bodies used to interpolate the exception straight into the response.
///
/// That handed an anonymous caller two things it could not otherwise get:
/// internal table names (`_dashboard`, `_cron_jobs`), and the action/table it
/// had just probed, echoed back. Vary the table name and the reply tells you
/// whether it exists -- an enumeration oracle over the whole schema, available
/// without ever authenticating.
///
/// What this does *not* cover: that the detail really does reach the log table
/// server-side. That needs a live request and a seeded database; this pins the
/// half whose loss is silent -- the client-facing body.
void main() {
  const catcher = Exceptions();

  group('permission failures', () {
    test('do not name the internal table or echo the probed action', () {
      final result = catcher.onPermissionException(
        const TableAccessDeniedException(
          table: '_dashboard',
          operation: 'metrics',
        ),
      );

      final handled = result.asHandled;
      expect(handled.statusCode, 403);
      expect(handled.body, {'error': 'Forbidden'});

      final body = '${handled.body}';
      expect(body, isNot(contains('_dashboard')));
      expect(body, isNot(contains('metrics')));
    });

    test('answer identically for a table and for a row', () {
      // Telling the two apart leaks whether a row matched, which is an
      // existence check on data the caller was just refused.
      final table = catcher
          .onPermissionException(
            const TableAccessDeniedException(table: 'users', operation: 'read'),
          )
          .asHandled;
      final row = catcher
          .onPermissionException(
            const RowAccessDeniedException(table: 'users', operation: 'read'),
          )
          .asHandled;

      expect(table.statusCode, row.statusCode);
      expect(table.body, row.body);
    });
  });

  group('an unregistered table', () {
    test('does not name the table that was probed', () {
      final handled = catcher
          .onSchemaException(
            const TableNotRegisteredException(table: '_cron_jobs'),
          )
          .asHandled;

      expect(handled.statusCode, 404);
      expect(handled.body, {'error': 'Not found'});
      expect('${handled.body}', isNot(contains('_cron_jobs')));
    });
  });
}
