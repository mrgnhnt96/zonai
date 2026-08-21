import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/providers/push_send_provider.dart';
import 'package:zonai_web/utils/push_row_targets.dart';

/// The send action appears exactly when the selected rows have somewhere to go.
///
/// Both directions are pinned deliberately. "It shows up when there is a
/// deviceToken column" is the easy half and the one a hand-check notices; the
/// half that rots silently is the absence — a table with no push feature
/// growing a bell icon because detection widened to "any text column called
/// token", and nobody browsing a push-enabled table ever seeing it.
///
/// The other half of this file is about who a selection actually reaches.
/// Every row dropped between "3 selected" and "Send to 2" has to be counted
/// and reported, because the dialog's count is the only place an operator
/// finds out that a row they picked is going nowhere.
void main() {
  ColumnShape column(
    String name,
    ColumnShapeKind kind, {
    bool isPrimaryKey = false,
    List<String> enumValues = const [],
  }) {
    return ColumnShape(
      name: name,
      kind: kind,
      isNullable: true,
      isPrimaryKey: isPrimaryKey,
      autoIncrement: false,
      sqlType: 'TEXT',
      enumValues: enumValues,
    );
  }

  List<String> namesOf(List<ColumnShape> shapes) => [for (final shape in shapes) shape.name];

  group('detection', () {
    test('no deviceToken column means no target at all', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        column('email', ColumnShapeKind.email),
        // Named like a token and typed as plain text. The action must not
        // appear for this: the engine refuses to push through a column whose
        // kind is not deviceToken, so a button here would offer a send that
        // cannot work.
        column('token', ColumnShapeKind.text),
      ];

      expect(pushRowTargets(table: 'users', columns: namesOf(shapes), columnShapes: shapes), isEmpty);
    });

    test('one deviceToken column is one target, indexed into the row', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        column('email', ColumnShapeKind.email),
        column('deviceToken', ColumnShapeKind.deviceToken),
      ];

      final targets = pushRowTargets(table: 'users', columns: namesOf(shapes), columnShapes: shapes);

      expect(targets, hasLength(1));
      expect(targets.single.label, 'users.deviceToken');
      // The index is what reads a cell, so it is the field a projection change
      // would silently break — the token would be read out of `email`.
      expect(targets.single.tokenIndex, 2);
    });

    test('a column the projection does not carry produces no target', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        column('deviceToken', ColumnShapeKind.deviceToken),
      ];

      // A target whose column is missing from the row would have to guess an
      // index, and every guess reads someone else's cell as a device token.
      expect(pushRowTargets(table: 'users', columns: const ['id'], columnShapes: shapes), isEmpty);
    });

    test('every deviceToken column is offered, in a stable order', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        column('iosToken', ColumnShapeKind.deviceToken),
        column('androidToken', ColumnShapeKind.deviceToken),
      ];

      final targets = pushRowTargets(table: 'users', columns: namesOf(shapes), columnShapes: shapes);

      // Sorted by column name, so the picker does not reorder itself between
      // renders just because the shapes arrived differently.
      expect(targets.map((t) => t.column), ['androidToken', 'iosToken']);
    });

    test('an enum column whose whole domain is platforms is the platform column', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        column('platform', ColumnShapeKind.enum_, enumValues: const ['ios', 'android']),
        column('deviceToken', ColumnShapeKind.deviceToken),
      ];

      final target = pushRowTargets(table: 'users', columns: namesOf(shapes), columnShapes: shapes).single;

      expect(target.platformColumn, 'platform');
      expect(target.platformIndex, 1);
    });

    test('an enum carrying anything else is not a platform column', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        // A status enum that happens to contain "android" would route half a
        // table through APNs. Nothing in the schema *declares* a platform
        // column — `push()` takes it as an argument — so the rule has to be
        // narrow enough that it cannot be anything else.
        column('status', ColumnShapeKind.enum_, enumValues: const ['ios', 'pending', 'banned']),
        column('deviceToken', ColumnShapeKind.deviceToken),
      ];

      expect(
        pushRowTargets(table: 'users', columns: namesOf(shapes), columnShapes: shapes).single.platformColumn,
        isNull,
      );
    });

    test('the text column docs/push.md recommends is a platform column', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        // `platform = $.text('platform', ...)` is the shape the push docs tell
        // people to write. Refusing it would mean the dashboard cannot route
        // the schema its own documentation recommends.
        column('platform', ColumnShapeKind.text),
        column('token', ColumnShapeKind.deviceToken),
      ];

      expect(
        pushRowTargets(table: 'device_tokens', columns: namesOf(shapes), columnShapes: shapes).single.platformColumn,
        'platform',
      );
    });

    test('the name is matched past case and underscores', () {
      for (final name in ['device_platform', 'devicePlatform', 'Platform']) {
        final shapes = [
          column('id', ColumnShapeKind.id, isPrimaryKey: true),
          column(name, ColumnShapeKind.text),
          column('token', ColumnShapeKind.deviceToken),
        ];

        expect(
          pushRowTargets(table: 'device_tokens', columns: namesOf(shapes), columnShapes: shapes).single.platformColumn,
          name,
          reason: 'a column named $name says which transport the row wants',
        );
      }
    });

    test('a text column named anything else is not a platform column', () {
      final shapes = [
        column('id', ColumnShapeKind.id, isPrimaryKey: true),
        // Free text nobody named for the job. Reading it would be the
        // dashboard guessing which transport a real user's notification goes
        // through.
        column('device_name', ColumnShapeKind.text),
        column('token', ColumnShapeKind.deviceToken),
      ];

      expect(
        pushRowTargets(table: 'device_tokens', columns: namesOf(shapes), columnShapes: shapes).single.platformColumn,
        isNull,
      );
    });
  });

  group('who a selection reaches', () {
    final shapes = [
      column('id', ColumnShapeKind.id, isPrimaryKey: true),
      column('platform', ColumnShapeKind.enum_, enumValues: const ['ios', 'android']),
      column('deviceToken', ColumnShapeKind.deviceToken),
    ];
    final columns = namesOf(shapes);
    final target = pushRowTargets(table: 'users', columns: columns, columnShapes: shapes).single;

    PushRecipientScan scan(List<List<Object?>> rows) =>
        scanPushRecipients(target: target, rows: rows, columns: columns, columnShapes: shapes);

    test('a row with no token is skipped and counted', () {
      final result = scan([
        [1, 'ios', 'token-a'],
        [2, 'android', null],
        // Blank rather than null: a column that has been written and cleared.
        [3, 'ios', '   '],
      ]);

      expect(result.recipients.map((r) => r.token), ['token-a']);
      // Counted, not swallowed: this is the number behind "2 selected rows
      // have no device token and will be skipped".
      expect(result.withoutToken, 2);
    });

    test('two rows sharing a token are sent to once', () {
      final result = scan([
        [1, 'ios', 'shared'],
        [2, 'ios', 'shared'],
      ]);

      // One phone, one notification. Sending twice would look like a bug in
      // the app rather than two rows holding the same registration.
      expect(result.recipients, hasLength(1));
      expect(result.duplicates, 1);
    });

    test('each row carries its own platform', () {
      final result = scan([
        [1, 'ios', 'token-a'],
        [2, 'android', 'token-b'],
        // Unparseable. The fan-out answers this with null — FCM — rather than
        // failing everyone else's notification over one row's typo.
        [3, 'windows-phone', 'token-c'],
      ]);

      expect(result.recipients.map((r) => r.platform), [DevicePlatform.ios, DevicePlatform.android, null]);
    });

    test('recipients are labelled by primary key, not by token', () {
      final result = scan([
        [42, 'ios', 'token-a'],
      ]);

      // The token is the one field an operator cannot check at a glance, so a
      // result list keyed on it is unreadable.
      expect(result.recipients.single.label, 'id=42');
    });

    test('a table with no primary key labels rows by position', () {
      final pkless = [
        column('platform', ColumnShapeKind.enum_, enumValues: const ['ios']),
        column('deviceToken', ColumnShapeKind.deviceToken),
      ];
      final pklessColumns = namesOf(pkless);
      final pklessTarget = pushRowTargets(table: 'devices', columns: pklessColumns, columnShapes: pkless).single;

      final result = scanPushRecipients(
        target: pklessTarget,
        rows: [
          ['ios', 'token-a'],
        ],
        columns: pklessColumns,
        columnShapes: pkless,
      );

      expect(result.recipients.single.label, 'Row 1');
    });
  });

  group('target selection', () {
    final shapes = [
      column('androidToken', ColumnShapeKind.deviceToken),
      column('iosToken', ColumnShapeKind.deviceToken),
    ];
    final targets = pushRowTargets(table: 'users', columns: namesOf(shapes), columnShapes: shapes);

    test('resolves a selected id', () {
      expect(resolvePushRowTarget(targets, 'users.iosToken').column, 'iosToken');
    });

    test('falls back to the first target when the selection is stale', () {
      // A dialog left open across a refresh must not land on a form that
      // refuses to send with nothing selected.
      expect(resolvePushRowTarget(targets, 'users.goneToken').column, 'androidToken');
      expect(resolvePushRowTarget(targets, null).column, 'androidToken');
    });
  });

  group('transport routing', () {
    test('the column choice defers to the row, and falls back to FCM', () {
      expect(
        resolvePushPlatform(choice: PushPlatformChoice.fromColumn, rowPlatform: DevicePlatform.ios),
        DevicePlatform.ios,
      );
      // Null is FCM, matching a fan-out with no platform column.
      expect(resolvePushPlatform(choice: PushPlatformChoice.fromColumn, rowPlatform: null), isNull);
    });

    test('an explicit choice overrides what the row says', () {
      // The override is the whole point of the control: an operator debugging
      // a sandbox mismatch needs to force APNs for a row stored as android.
      expect(
        resolvePushPlatform(choice: PushPlatformChoice.ios, rowPlatform: DevicePlatform.android),
        DevicePlatform.ios,
      );
      expect(resolvePushPlatform(choice: PushPlatformChoice.defaultFcm, rowPlatform: DevicePlatform.ios), isNull);
    });
  });

  group('outcome wording', () {
    test('acceptance does not claim delivery', () {
      final text = describePushSendResult(
        const PushTestSendResult(status: PushTestSendStatus.accepted, token: 'abc', transport: 'fcm'),
      );

      // Neither transport offers a delivery receipt, and this dialog exists to
      // debug the case where a token is accepted and nothing arrives. Saying
      // "delivered" would be a lie in exactly that case.
      expect(text, contains('accepted'));
      expect(text.toLowerCase(), isNot(contains('delivered')));
    });

    test('BadDeviceToken names the sandbox mismatch rather than blaming the device', () {
      final text = describePushSendResult(
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
      final text = describePushSendResult(
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
      final text = describePushSendResult(
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

    test('a failure whose own words already say it does not say it twice', () {
      final text = describePushSendResult(
        const PushTestSendResult(
          status: PushTestSendStatus.failed,
          token: 'abc',
          transport: 'none',
          // Verbatim from the engine, and it ends with the same sentence the
          // prefix would add. Read once per row in a list of results, the
          // stutter is what an operator stops reading.
          detail: 'AppConfig.push is not configured, so there is no transport to send through. Nothing was sent.',
        ),
      );

      expect('Nothing was sent'.allMatches(text), hasLength(1));
    });
  });

  group('send summary', () {
    test('a mixed send reports every count, not a verdict', () {
      // Four accepted and one rejected is neither a success nor a failure, and
      // a single word for it would have to pick one — which is how the
      // rejected token stops being looked at.
      expect(describePushSendSummary(accepted: 4, rejected: 1, failed: 0), '4 accepted · 1 rejected');
    });

    test('counts that are zero are left out', () {
      expect(describePushSendSummary(accepted: 2, rejected: 0, failed: 0), '2 accepted');
      expect(describePushSendSummary(accepted: 0, rejected: 0, failed: 3), '3 failed');
    });

    test('nothing at all still says so', () {
      expect(describePushSendSummary(accepted: 0, rejected: 0, failed: 0), 'Nothing was sent.');
    });
  });
}
