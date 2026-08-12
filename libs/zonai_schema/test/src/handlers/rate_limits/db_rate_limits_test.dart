import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The host passes `customOperation: null` on purpose whenever it can't
/// validate the caller-supplied operation name in-process (rules running in a
/// worker), so the limiter falls back to the coarse per-table bucket instead of
/// trusting the name. Resolving a policy for that request has to work rather
/// than throw — a throw here surfaces as a 500 on every custom-operation
/// request the server can't pre-validate.
void main() {
  final items = table('items', _ItemTable.new);

  group('dispatch resolves .custom', () {
    test(
      'with a null operation name for a table with no rate limits',
      () async {
        final rateLimits = DbRateLimits(rateLimits: []);

        final response = await rateLimits.dispatch(
          RateLimitRequest(table: 'items', operation: .custom),
        );

        expect(response.policy, RateLimitPolicy.defaultPolicy);
      },
    );

    test('with a null operation name for a table with rate limits', () async {
      final rateLimits = DbRateLimits(rateLimits: [_ItemRateLimits(items)]);

      final response = await rateLimits.dispatch(
        RateLimitRequest(table: 'items', operation: .custom),
      );

      expect(response.policy, _coarse);
    });

    test('with a named operation for a table with rate limits', () async {
      final rateLimits = DbRateLimits(rateLimits: [_ItemRateLimits(items)]);

      final response = await rateLimits.dispatch(
        RateLimitRequest(
          table: 'items',
          operation: .custom,
          customOperation: 'fill',
        ),
      );

      expect(response.policy, _fill);
    });

    test('with a named operation for a table with no rate limits', () async {
      final rateLimits = DbRateLimits(rateLimits: []);

      final response = await rateLimits.dispatch(
        RateLimitRequest(
          table: 'items',
          operation: .custom,
          customOperation: 'fill',
        ),
      );

      expect(response.policy, RateLimitPolicy.defaultPolicy);
    });

    // The worker doesn't get the object above -- it gets whatever survives
    // `toJson` and comes back through `fromRequest`, which is where a dropped
    // or defaulted name would go unnoticed.
    test('with an operation name carried over the worker hop', () async {
      final rateLimits = DbRateLimits(rateLimits: [_ItemRateLimits(items)]);

      for (final (sent, expected) in [(null, _coarse), ('fill', _fill)]) {
        final wire = RateLimitRequest(
          table: 'items',
          operation: .custom,
          customOperation: sent,
        ).toJson();

        final response = await rateLimits.dispatch(
          RateLimitRequest.fromRequest(
            Request.fromJson(wire) as UnknownRequest,
          ),
        );

        expect(response.policy, expected, reason: 'sent customOperation=$sent');
      }
    });
  });
}

const _fill = RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 1));
const _coarse = RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 1));

final class _Item {
  const _Item({required this.id});

  final String id;
}

final class _ItemTable extends Table<_Item> {
  _ItemTable(super.$) : id = $.text('id', (s) => s.id);

  @override
  _Item fromRow(RowReader read) => _Item(id: read(id));

  final TextColumn id;
}

final class _ItemRateLimits extends TableRateLimits<_ItemTable, _Item> {
  const _ItemRateLimits(super.schema);

  @override
  Future<RateLimitPolicy?> customPolicy(String? operation) async {
    return switch (operation) {
      'fill' => _fill,
      // The name couldn't be validated, so no per-name bucket exists to
      // police -- one coarse policy covers every custom operation here.
      null => _coarse,
      _ => .defaultPolicy,
    };
  }
}
