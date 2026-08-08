import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

UnknownRequest _request(Map<String, dynamic> payload) {
  return UnknownRequest(payload: payload, path: 'unused', id: 'req-1');
}

void main() {
  group('RowRulesRequest.fromRequest', () {
    test('throws when an update-operation payload has no "updates" key at all '
        '(a stale, pre-issue-#23 host) instead of silently treating after as '
        'identical to before', () {
      final request = _request({
        'table': 'items',
        'operation': 'update',
        'data': {'id': 1},
      });

      expect(
        () => RowRulesRequest.fromRequest(request),
        throwsA(isA<StaleRowRulesRequestException>()),
      );
    });

    test(
      'parses normally when "updates" is present, even as an empty list',
      () {
        final request = _request({
          'table': 'items',
          'operation': 'update',
          'data': {'id': 1},
          'updates': <Object?>[],
        });

        final parsed = RowRulesRequest.fromRequest(request);
        expect(parsed.updates, isEmpty);
      },
    );

    test('does not require "updates" for non-update operations', () {
      final request = _request({
        'table': 'items',
        'operation': 'view',
        'data': {'id': 1},
      });

      final parsed = RowRulesRequest.fromRequest(request);
      expect(parsed.updates, isEmpty);
    });
  });

  group('BatchRowRulesRequest.fromRequest', () {
    test('throws when an update-operation payload has no "updates" key at all '
        '(a stale, pre-issue-#23 host)', () {
      final request = _request({
        'table': 'items',
        'operation': 'update',
        'rows': [
          {'id': 1},
        ],
      });

      expect(
        () => BatchRowRulesRequest.fromRequest(request),
        throwsA(isA<StaleRowRulesRequestException>()),
      );
    });

    test(
      'parses normally when "updates" is present, even as an empty list',
      () {
        final request = _request({
          'table': 'items',
          'operation': 'update',
          'rows': [
            {'id': 1},
          ],
          'updates': <Object?>[],
        });

        final parsed = BatchRowRulesRequest.fromRequest(request);
        expect(parsed.updates, isEmpty);
      },
    );

    test('does not require "updates" for non-update operations', () {
      final request = _request({
        'table': 'items',
        'operation': 'delete',
        'rows': [
          {'id': 1},
        ],
      });

      final parsed = BatchRowRulesRequest.fromRequest(request);
      expect(parsed.updates, isEmpty);
    });
  });
}
