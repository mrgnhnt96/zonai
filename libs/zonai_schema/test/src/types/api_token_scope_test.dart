import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group(ApiTokenScope, () {
    test('round-trips through JSON', () {
      const scope = ApiTokenScope(
        tables: {'orders', 'line_items'},
        operations: {TableOperation.view, TableOperation.list},
        customOperations: {'close'},
        admin: true,
        canEdit: true,
        rateLimit: RateLimitPolicy(
          maxRequests: 1000,
          window: Duration(minutes: 5),
        ),
      );

      final decoded = ApiTokenScope.fromJson(scope.toJson());

      expect(decoded.tables, {'orders', 'line_items'});
      expect(decoded.operations, {TableOperation.view, TableOperation.list});
      expect(decoded.customOperations, {'close'});
      expect(decoded.admin, isTrue);
      expect(decoded.canEdit, isTrue);
      expect(decoded.rateLimit?.maxRequests, 1000);
      expect(decoded.rateLimit?.window, const Duration(minutes: 5));
    });

    test('an unparsable scope decodes to nothing, not to everything', () {
      // The failure mode worth pinning: a corrupted or truncated `scope`
      // column must leave the token able to do nothing, never to do all of it.
      final decoded = ApiTokenScope.fromJson(const {});

      expect(decoded.tables, isEmpty);
      expect(decoded.operations, isEmpty);
      expect(decoded.admin, isFalse);
      expect(decoded.canEdit, isFalse);
      expect(decoded.allowsTable('orders'), isFalse);
      expect(decoded.allowsOperation(TableOperation.view), isFalse);
    });

    test('ApiTokenScope.none allows nothing', () {
      expect(ApiTokenScope.none.allowsTable('orders'), isFalse);
      expect(ApiTokenScope.none.allowsTable(ApiTokenScope.wildcard), isFalse);
      expect(ApiTokenScope.none.allowsOperation(TableOperation.list), isFalse);
      expect(ApiTokenScope.none.allowsCustomOperation('close'), isFalse);
    });

    test('an unknown operation name is dropped rather than admitted', () {
      final decoded = ApiTokenScope.fromJson(const {
        'tables': ['orders'],
        'operations': ['list', 'teleport'],
      });

      expect(decoded.operations, {TableOperation.list});
    });

    test('the wildcard covers any table', () {
      const scope = ApiTokenScope(
        tables: {ApiTokenScope.wildcard},
        operations: {TableOperation.list},
      );

      expect(scope.allowsTable('orders'), isTrue);
      expect(scope.allowsTable('anything_at_all'), isTrue);
      // The gate excludes internal tables itself; the scope type is only ever
      // asked "is this named", and answers honestly.
      expect(scope.allowsTable('_api_tokens'), isTrue);
    });

    test('an unlisted operation is denied even when the table matches', () {
      const scope = ApiTokenScope(
        tables: {ApiTokenScope.wildcard},
        operations: {TableOperation.list, TableOperation.view},
      );

      expect(scope.allowsOperation(TableOperation.list), isTrue);
      expect(scope.allowsOperation(TableOperation.delete), isFalse);
      expect(scope.allowsOperation(TableOperation.create), isFalse);
    });

    test('a bare "tables": "*" string is read as the wildcard', () {
      // Tolerated on the way in because it is what a human writes by hand;
      // toJson always emits a list.
      final decoded = ApiTokenScope.fromJson(const {
        'tables': '*',
        'operations': ['list'],
      });

      expect(decoded.tables, {ApiTokenScope.wildcard});
      expect(decoded.allowsTable('orders'), isTrue);
      expect(decoded.toJson()['tables'], ['*']);
    });

    test('custom operations honour their own wildcard', () {
      const scope = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        customOperations: {ApiTokenScope.wildcard},
      );

      expect(scope.allowsCustomOperation('close'), isTrue);

      const named = ApiTokenScope(
        tables: {'orders'},
        operations: {},
        customOperations: {'close'},
      );

      expect(named.allowsCustomOperation('close'), isTrue);
      expect(named.allowsCustomOperation('reopen'), isFalse);
    });
  });
}
