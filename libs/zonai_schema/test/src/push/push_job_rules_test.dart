import 'package:test/test.dart';
import 'package:zonai_schema/src/internal/rules/push_job_row_rules.dart';
import 'package:zonai_schema/src/internal/rules/push_job_table_rules.dart';
import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Who may delete a `_push_jobs` row.
///
/// This is the same hazard `cleanup_push_jobs_cron_test` guards from the
/// retention side, reached from the API instead: **a running job's row is its
/// fan-out cursor.** Delete one and the next drain finds no checkpoint,
/// restarts from the top, and re-notifies every recipient it had already
/// reached. From retention that is a bug; from an unauthenticated endpoint it
/// is a way to make someone else's app spam its users on demand.
///
/// Worth its own file even though the two rule classes only restate the
/// inherited default. That restatement is the point — it pins the policy for
/// `_push_jobs` independently of `BaseTableRules`, so a future loosening of
/// the framework-wide default cannot quietly reach this table. Nothing
/// checked either the override or the default until now.
void main() {
  /// A caller with the given admin claims. Deliberately built through
  /// `Jwt.fromJson`, the same door a real request arrives by — hand-building
  /// the record would let a test pass against a shape the parser cannot
  /// actually produce.
  Jwt jwt({required bool isAdmin, bool? canEdit}) => Jwt.fromJson({
    'userId': 'u1',
    'table': 'users',
    'user': <String, dynamic>{},
    'jwtId': 'j1',
    'expiresAt':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
    'claims': <String, dynamic>{},
    'admin': {'isAdmin': isAdmin, 'canEdit': canEdit},
  });

  final row = PushJobEntry.create(
    message: const PushMessage(title: 'a', body: 'b'),
    targetTable: 'device_tokens',
    targetColumn: 'token',
    where: null,
  );

  final table = PushJobTableRules();
  final rows = PushJobRowRules();

  group('deleting a push job requires an editing admin', () {
    test('an anonymous caller cannot', () async {
      expect(await table.canDelete(null), isFalse);
      expect(await rows.canDelete(null, row), isFalse);
    });

    test('a signed-in non-admin cannot', () async {
      final user = jwt(isAdmin: false);

      expect(await table.canDelete(user), isFalse);
      expect(await rows.canDelete(user, row), isFalse);
    });

    test('a read-only admin cannot', () async {
      // `isAdmin` without `canEdit` is the dashboard viewer. Deleting a job
      // row is a write, and a viewer having it would be the quiet kind of
      // privilege bug — everything looks read-only until the fan-out
      // restarts.
      final viewer = jwt(isAdmin: true, canEdit: false);

      expect(await table.canDelete(viewer), isFalse);
      expect(await rows.canDelete(viewer, row), isFalse);
    });

    test('an admin whose canEdit is absent cannot', () async {
      // `canEdit: null` is what `Jwt.fromJson` yields when the claim is
      // missing entirely. Absent must read as "no", never as "unset, so
      // allow" — the switch is on `true`, not on `!= false`, precisely so a
      // malformed token cannot widen into permission.
      final unclear = jwt(isAdmin: true);

      expect(await table.canDelete(unclear), isFalse);
      expect(await rows.canDelete(unclear, row), isFalse);
    });

    test('an editing admin can', () async {
      final admin = jwt(isAdmin: true, canEdit: true);

      expect(await table.canDelete(admin), isTrue);
      expect(await rows.canDelete(admin, row), isTrue);
    });

    test('the cron can, since retention runs as one', () async {
      // `_cleanup_push_jobs` deletes through the same rules. If CronJwt ever
      // stopped satisfying them, retention would fail silently and the table
      // would grow forever — the `_log` outcome the cron exists to avoid.
      expect(await table.canDelete(CronJwt()), isTrue);
      expect(await rows.canDelete(CronJwt(), row), isTrue);
    });
  });

  group('reading a push job requires an admin', () {
    test('anonymous and non-admin callers cannot view or list', () async {
      expect(await table.canView(null), isFalse);
      expect(await table.canList(null), isFalse);
      expect(await rows.canView(null, row), isFalse);

      final user = jwt(isAdmin: false);
      expect(await table.canView(user), isFalse);
      expect(await table.canList(user), isFalse);
      expect(await rows.canView(user, row), isFalse);
    });

    test(
      'a read-only admin may view, since viewing is why they exist',
      () async {
        // Unlike delete, `canView` keys off `isAdmin` rather than `canEdit`:
        // the job row is the thing you read when someone complains a
        // notification never arrived.
        final viewer = jwt(isAdmin: true, canEdit: false);

        expect(await table.canView(viewer), isTrue);
        expect(await table.canList(viewer), isTrue);
        expect(await rows.canView(viewer, row), isTrue);
      },
    );
  });

  group('creating and updating a push job requires an editing admin', () {
    test('a non-admin can do neither', () async {
      final user = jwt(isAdmin: false);

      expect(await table.canCreate(user), isFalse);
      expect(await table.canUpdate(user), isFalse);
    });

    test('an editing admin can do both', () async {
      final admin = jwt(isAdmin: true, canEdit: true);

      expect(await table.canCreate(admin), isTrue);
      expect(await table.canUpdate(admin), isTrue);
    });
  });
}
