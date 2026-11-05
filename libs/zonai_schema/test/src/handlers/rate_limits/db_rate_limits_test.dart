import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
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
  group('keyed create counters', () {
    Future<RateLimitResponse> ask(
      DbRateLimits rateLimits, {
      RateLimitOperation operation = .create,
      String? counter,
      String? value,
    }) {
      // Through the wire, the way the worker receives it.
      final wire = RateLimitRequest(
        table: 'items',
        operation: operation,
        counter: counter,
        value: value,
      ).toJson();
      return rateLimits.dispatch(
        RateLimitRequest.fromRequest(Request.fromJson(wire) as UnknownRequest),
      );
    }

    test('a table without them offers none', () async {
      final response = await ask(
        DbRateLimits(rateLimits: [_ItemRateLimits(items)]),
      );

      expect(response.counters, isEmpty);
      expect(response.policy, RateLimitPolicy.defaultPolicy);
    });

    test('are offered with their columns for creates only', () async {
      final rateLimits = DbRateLimits(
        rateLimits: [_KeyedItemRateLimits(items)],
      );

      final create = await ask(rateLimits);
      expect(create.counters, {'app': 'api_key', 'device': 'install_id'});
      expect(create.policy, isNull, reason: 'the table dropped per-IP');

      final update = await ask(rateLimits, operation: .update);
      expect(update.counters, isEmpty);
    });

    test('key a value through the table, or use it as is', () async {
      final rateLimits = DbRateLimits(
        rateLimits: [_KeyedItemRateLimits(items)],
      );

      final known = await ask(rateLimits, counter: 'app', value: 'pk_live_1');
      expect(known.key, 'app-1');
      expect(known.policy, _plan);

      final device = await ask(rateLimits, counter: 'device', value: 'd1');
      expect(device.key, 'd1');
      expect(device.policy, _perDevice);
    });

    test('count a value the table turns down as keyless', () async {
      final rateLimits = DbRateLimits(
        rateLimits: [_KeyedItemRateLimits(items)],
      );

      for (final value in ['pk_unknown', 'pk_empty', null]) {
        final response = await ask(rateLimits, counter: 'app', value: value);
        expect(response.key, isNull, reason: '$value');
        expect(response.policy, _keyless, reason: '$value');
      }
    });

    test('refuse an unknown counter or a non-create operation', () async {
      final rateLimits = DbRateLimits(
        rateLimits: [_KeyedItemRateLimits(items)],
      );

      expect(
        () => ask(rateLimits, counter: 'nope', value: 'x'),
        throwsStateError,
      );
      expect(
        () => ask(rateLimits, operation: .update, counter: 'app', value: 'x'),
        throwsStateError,
      );
    });

    test('must have distinct names', () async {
      final rateLimits = DbRateLimits(
        rateLimits: [_KeyedItemRateLimits(items, duplicate: true)],
      );

      expect(() => ask(rateLimits), throwsStateError);
    });

    test('must have a name that fits a bucket key', () {
      for (final name in ['', 'App', 'a#b', 'a:b', '1st', 'has space']) {
        expect(
          () => RateLimitCounter(
            name: name,
            column: items.apiKey,
            policy: (_) async => null,
          ),
          throwsArgumentError,
          reason: name,
        );
      }
      expect(
        RateLimitCounter(
          name: 'per_app_2',
          column: items.apiKey,
          policy: (_) async => null,
        ).columnName,
        'api_key',
      );
    });

    test('the response survives the hop back to the host', () {
      final response = RateLimitResponse(
        id: 'r1',
        policy: _plan,
        counters: {'app': 'api_key'},
        key: 'app-1',
      );

      final back = RateLimitResponse.fromJson(response.toJson());
      expect(back.policy?.maxRequests, _plan.maxRequests);
      expect(back.policy?.window, _plan.window);
      expect(back.counters, {'app': 'api_key'});
      expect(back.key, 'app-1');

      final bare = RateLimitResponse.fromJson(
        RateLimitResponse(id: 'r2', policy: null).toJson(),
      );
      expect(bare.counters, isEmpty);
      expect(bare.key, isNull);
    });
  });
}

const _fill = RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 1));
const _coarse = RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 1));
const _plan = RateLimitPolicy(maxRequests: 100, window: Duration(minutes: 5));
const _keyless = RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 5));
const _perDevice = RateLimitPolicy(
  maxRequests: 20,
  window: Duration(minutes: 5),
);

final class _Item {
  const _Item({
    required this.id,
    required this.apiKey,
    required this.installId,
  });

  final String id;
  final String apiKey;
  final String installId;
}

final class _ItemTable extends Table<_Item> {
  _ItemTable(super.$)
    : id = $.text('id', (s) => s.id),
      apiKey = $.text('api_key', (s) => s.apiKey),
      installId = $.text('install_id', (s) => s.installId);

  @override
  _Item fromRow(RowReader read) =>
      _Item(id: read(id), apiKey: read(apiKey), installId: read(installId));

  final TextColumn id;
  final TextColumn apiKey;
  final TextColumn installId;
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

final class _KeyedItemRateLimits extends TableRateLimits<_ItemTable, _Item> {
  const _KeyedItemRateLimits(super.schema, {this.duplicate = false});

  final bool duplicate;

  @override
  Future<RateLimitPolicy?> createPolicy() async => null;

  @override
  List<RateLimitCounter> createCounters() => [
    RateLimitCounter(
      name: 'app',
      column: schema.apiKey,
      key: (apiKey) async => switch (apiKey) {
        'pk_live_1' => 'app-1',
        'pk_empty' => '',
        _ => null,
      },
      policy: (appId) async => appId == null ? _keyless : _plan,
    ),
    RateLimitCounter(
      name: duplicate ? 'app' : 'device',
      column: schema.installId,
      policy: (_) async => _perDevice,
    ),
  ];
}
