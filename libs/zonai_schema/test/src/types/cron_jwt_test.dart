import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group(CronJwt, () {
    test('has elevated admin privileges', () {
      final jwt = CronJwt();

      expect(jwt.admin.isAdmin, isTrue);
      expect(jwt.admin.canEdit, isTrue);
      expect(jwt.userId.value, '__cron__');
      expect(jwt.jwtId.value, '__cron__');
      expect(jwt.isExpired, isFalse);
    });

    test('toJson uses worker IPC sentinel', () {
      expect(CronJwt().toJson(), {'CRON': true});
    });
  });

  group('Jwt cron worker payload', () {
    test('isCronWorkerPayload matches only CRON: true', () {
      expect(Jwt.isCronWorkerPayload({'CRON': true}), isTrue);
      expect(Jwt.isCronWorkerPayload({'CRON': false}), isFalse);
      expect(Jwt.isCronWorkerPayload({'CRON': 'true'}), isFalse);
      expect(Jwt.isCronWorkerPayload({}), isFalse);
    });

    test('fromJson reconstructs CronJwt from sentinel', () {
      final jwt = Jwt.fromJson({'CRON': true});

      expect(jwt, isA<CronJwt>());
      expect(jwt.admin.isAdmin, isTrue);
      expect(jwt.admin.canEdit, isTrue);
    });

    test('maybeFromJson round-trips CronJwt JSON', () {
      final jwt = Jwt.maybeFromJson(CronJwt().toJson());

      expect(jwt, isA<CronJwt>());
    });

    test('maybeFromJson returns null for invalid jwt JSON', () {
      expect(Jwt.maybeFromJson({}), isNull);
      expect(Jwt.maybeFromJson(null), isNull);
    });
  });

  group('worker request JWT round-trip', () {
    test('GetRecordRequest preserves CronJwt over JSON', () {
      final request = GetRecordRequest(
        table: 'items',
        where: Eq('id', 'item-1'),
        jwt: CronJwt(),
      );

      final roundTripped = GetRecordRequest.fromJson(request.toJson());

      expect(roundTripped.jwt, isA<CronJwt>());
      expect(roundTripped.table, 'items');
    });

    test('CreateRecordRequest preserves CronJwt over JSON', () {
      final parent = StartCronsRequest();
      final request = CreateRecordRequest(
        table: 'items',
        objects: [
          {'id': 'item-1'},
        ],
        parent: parent,
        jwt: CronJwt(),
      );

      final roundTripped = CreateRecordRequest.fromJson(request.toJson());

      expect(roundTripped.jwt, isA<CronJwt>());
      expect(roundTripped.parent.jwt, isA<CronJwt>());
    });
  });
}
