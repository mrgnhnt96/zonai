import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/utils/push_test_targets.dart';

/// The test-send panel appears exactly when the project has somewhere to send.
///
/// Both directions are pinned deliberately. "It shows up when there is a
/// deviceToken column" is the easy half and the one a hand-check notices; the
/// half that rots silently is the absence — a project with no push feature
/// growing a push panel because detection widened to "any text column called
/// token", and nobody looking at a push-enabled project ever seeing it.
void main() {
  ColumnShape column(String name, ColumnShapeKind kind) =>
      ColumnShape(name: name, kind: kind, isNullable: true, isPrimaryKey: false, autoIncrement: false, sqlType: 'TEXT');

  TableSchemaShape table(String name, List<ColumnShape> columns, {bool isView = false}) =>
      TableSchemaShape(table: name, columns: columns, isView: isView);

  group('detection', () {
    test('no deviceToken column anywhere means no targets at all', () {
      final schemas = {
        'users': table('users', [
          column('id', ColumnShapeKind.id),
          column('email', ColumnShapeKind.email),
          // Named like a token and typed as plain text. The panel must not
          // appear for this: the engine refuses to push through a column
          // whose kind is not deviceToken, so a panel here would offer a
          // send that cannot work.
          column('token', ColumnShapeKind.text),
        ]),
        'posts': table('posts', [column('id', ColumnShapeKind.id)]),
      };

      expect(pushTestTargets(schemas), isEmpty);
    });

    test('an empty schema means no targets', () {
      expect(pushTestTargets(const {}), isEmpty);
    });

    test('one deviceToken column is one target', () {
      final schemas = {
        'users': table('users', [column('id', ColumnShapeKind.id), column('deviceToken', ColumnShapeKind.deviceToken)]),
      };

      expect(pushTestTargets(schemas), [const PushTestTarget(table: 'users', column: 'deviceToken')]);
    });

    test('every deviceToken column is offered, across tables and within one', () {
      final schemas = {
        'users': table('users', [
          column('id', ColumnShapeKind.id),
          column('iosToken', ColumnShapeKind.deviceToken),
          column('androidToken', ColumnShapeKind.deviceToken),
        ]),
        'admins': table('admins', [column('pushToken', ColumnShapeKind.deviceToken)]),
        'posts': table('posts', [column('body', ColumnShapeKind.text)]),
      };

      // Sorted by "table.column", so the picker does not reorder itself
      // between renders just because the shapes map iterated differently.
      expect(pushTestTargets(schemas).map((t) => t.label), [
        'admins.pushToken',
        'users.androidToken',
        'users.iosToken',
      ]);
    });

    test('a view carrying a deviceToken column is a target', () {
      final schemas = {
        'active_devices': table('active_devices', [column('deviceToken', ColumnShapeKind.deviceToken)], isView: true),
      };

      // The engine checks the column's *kind*, not where it lives, so
      // excluding views here would hide a target the server would accept.
      expect(pushTestTargets(schemas), hasLength(1));
    });
  });

  group('target selection', () {
    final targets = pushTestTargets({
      'users': table('users', [
        column('androidToken', ColumnShapeKind.deviceToken),
        column('iosToken', ColumnShapeKind.deviceToken),
      ]),
    });

    test('resolves a selected id', () {
      expect(resolvePushTestTarget(targets, 'users.iosToken').column, 'iosToken');
    });

    test('falls back to the first target when the selection is stale', () {
      // A dashboard left open across a rename must not land on a form that
      // refuses to send with nothing selected.
      expect(resolvePushTestTarget(targets, 'users.goneToken').column, 'androidToken');
      expect(resolvePushTestTarget(targets, null).column, 'androidToken');
    });
  });

  group('outcome wording', () {
    test('acceptance does not claim delivery', () {
      final text = describePushTestResult(
        const PushTestSendResult(status: PushTestSendStatus.accepted, token: 'abc', transport: 'fcm'),
      );

      // Neither transport offers a delivery receipt, and this panel exists to
      // debug the case where a token is accepted and nothing arrives. Saying
      // "delivered" would be a lie in exactly that case.
      expect(text, contains('accepted'));
      expect(text.toLowerCase(), isNot(contains('delivered')));
    });

    test('BadDeviceToken names the sandbox mismatch rather than blaming the device', () {
      final text = describePushTestResult(
        const PushTestSendResult(
          status: PushTestSendStatus.rejected,
          token: 'abc',
          transport: 'apns',
          reason: PushRejectionReason.unregistered,
          detail: '400 BadDeviceToken',
        ),
      );

      // The provider's own words survive to the operator...
      expect(text, contains('BadDeviceToken'));
      // ...and so does the reading that actually saves them an afternoon: the
      // token is valid, it was issued by the other APNs environment.
      expect(text, contains('useSandbox'));
    });

    test('a rejection with no detail still says which transport and why', () {
      final text = describePushTestResult(
        const PushTestSendResult(
          status: PushTestSendStatus.rejected,
          token: 'abc',
          transport: 'fcm',
          reason: PushRejectionReason.unregistered,
        ),
      );

      expect(text, contains('FCM'));
      expect(text, contains('uninstalled'));
    });

    test('a failure reproduces the reason verbatim', () {
      final text = describePushTestResult(
        const PushTestSendResult(
          status: PushTestSendStatus.failed,
          token: 'abc',
          transport: 'none',
          detail: 'AppConfig.push is not configured',
        ),
      );

      expect(text, contains('Nothing was sent'));
      expect(text, contains('AppConfig.push is not configured'));
    });
  });
}
