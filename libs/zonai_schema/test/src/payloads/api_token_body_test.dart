import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/zonai_schema.dart';

/// What `POST /admin/tokens` accepts, and what it refuses before a row exists.
///
/// The dashboard is the second way to mint a credential, and the first one
/// (`zonai db token create`) already refuses each of these. Two ways in means
/// two chances to disagree about what a scope means, so the defaults here are
/// asserted against the CLI's rather than merely being present.
void main() {
  Map<String, dynamic> valid([Map<String, dynamic> overrides = const {}]) => {
    'name': 'nightly-backup',
    'tables': ['orders'],
    'operations': ['view', 'list'],
    ...overrides,
  };

  group('ApiTokenCreateBody', () {
    test('reads the shape the dashboard sends', () {
      final body = ApiTokenCreateBody.fromJson(
        valid({
          'customOperations': ['close'],
          'claims': {'role': 'reporting'},
          'expiresAt': '2026-11-01T00:00:00.000Z',
        }),
      );

      expect(body.name, 'nightly-backup');
      expect(body.scope.tables, {'orders'});
      expect(body.scope.operations, {TableOperation.view, TableOperation.list});
      expect(body.scope.customOperations, {'close'});
      expect(body.claims['role'], 'reporting');
      expect(body.expiresAt, DateTime.utc(2026, 11));
    });

    test('a token is an admin unless the body says otherwise', () {
      // Same default the CLI has. A non-admin token is denied by the DEFAULT
      // rules, so it reads as broken rather than as narrow, and the dashboard
      // must not quietly hand out the broken kind.
      expect(ApiTokenCreateBody.fromJson(valid()).scope.admin, isTrue);
      expect(
        ApiTokenCreateBody.fromJson(valid({'admin': false})).scope.admin,
        isFalse,
      );
    });

    test('an absent canEdit derives rather than pinning to false', () {
      // The failure this prevents: a `--write` token whose body omitted
      // `canEdit` would carry a scope it cannot spend, because
      // `BaseTableRules.canCreate` checks `canEdit` alone.
      final writer = ApiTokenCreateBody.fromJson(
        valid({
          'operations': ['create', 'update'],
        }),
      );
      expect(writer.scope.canEdit, isTrue);

      final reader = ApiTokenCreateBody.fromJson(valid());
      expect(reader.scope.canEdit, isFalse);

      final pinned = ApiTokenCreateBody.fromJson(
        valid({
          'operations': ['create'],
          'canEdit': false,
        }),
      );
      expect(pinned.scope.canEdit, isFalse);
    });

    test('null and absent expiry both mean never', () {
      expect(ApiTokenCreateBody.fromJson(valid()).expiresAt, isNull);
      expect(
        ApiTokenCreateBody.fromJson(valid({'expiresAt': null})).expiresAt,
        isNull,
      );
      expect(
        ApiTokenCreateBody.fromJson(valid({'expiresAt': '  '})).expiresAt,
        isNull,
      );
    });

    test('a bare "tables": "*" string is read as the wildcard', () {
      final body = ApiTokenCreateBody.fromJson(valid({'tables': '*'}));

      expect(body.scope.tables, {ApiTokenScope.wildcard});
    });

    group('refused before a row exists', () {
      test('a missing or blank name', () {
        for (final name in [null, '', '   ', 42]) {
          expect(
            () => ApiTokenCreateBody.fromJson(valid({'name': name})),
            throwsA(isA<ArgumentError>()),
            reason: 'name=$name',
          );
        }
      });

      test('an operation that does not exist', () {
        expect(
          () => ApiTokenCreateBody.fromJson(
            valid({
              'operations': ['list', 'teleport'],
            }),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '$e',
              'message',
              allOf(contains('teleport'), contains('delete')),
            ),
          ),
        );
      });

      test('an expiry that is not a timestamp', () {
        expect(
          () => ApiTokenCreateBody.fromJson(valid({'expiresAt': 'soon'})),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => ApiTokenCreateBody.fromJson(valid({'expiresAt': 90})),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('half a binding', () {
        // A binding that names a table and no row produces a token that
        // authenticates and then matches nothing, which reads as "the rules
        // are wrong" from every angle except this one.
        expect(
          () => ApiTokenCreateBody.fromJson(valid({'boundTable': 'users'})),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => ApiTokenCreateBody.fromJson(valid({'boundUserId': 'user_1'})),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test('the deeper refusals are left to createApiToken', () {
      // Deliberately NOT refused here: an internal table, an empty scope, and
      // `canEdit` without `admin` all belong to `ZonaiDb.createApiToken`,
      // which is the one path both the CLI and this body reach. A second copy
      // of those rules is a second thing to keep in step.
      expect(
        ApiTokenCreateBody.fromJson(
          valid({
            'tables': ['_api_tokens'],
          }),
        ).scope.tables,
        {'_api_tokens'},
      );
      expect(
        ApiTokenCreateBody.fromJson(
          valid({'tables': <String>[], 'operations': <String>[]}),
        ).scope.tables,
        isEmpty,
      );
    });
  });
}
