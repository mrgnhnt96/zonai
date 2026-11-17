import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group(CronRunResult, () {
    test('round-trips through JSON', () {
      const result = CronRunResult(
        name: 'match_esa',
        ok: true,
        ms: 812,
        changes: {
          'transactions': {'update': 1},
          'esa_candidates': {'create': 3},
        },
      );

      final json = result.toJson();
      final decoded = CronRunResult.fromJson(json);

      expect(json.containsKey('error'), isFalse);
      expect(decoded.name, 'match_esa');
      expect(decoded.ok, isTrue);
      expect(decoded.ms, 812);
      expect(decoded.changes, result.changes);
      expect(decoded.error, isNull);
    });

    test('a failed run carries its error', () {
      final decoded = CronRunResult.fromJson({
        'name': 'boom',
        'ok': false,
        'ms': 3.0,
        'error': 'Bad state: boom',
      });

      expect(decoded.ok, isFalse);
      expect(decoded.ms, 3);
      expect(decoded.changes, isEmpty);
      expect(decoded.error, 'Bad state: boom');
    });
  });
}
