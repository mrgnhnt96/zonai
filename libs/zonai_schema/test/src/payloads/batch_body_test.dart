import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';

void main() {
  group(BatchBody, () {
    BatchBody roundTrip(BatchBody body) => BatchBody.fromJson(
      jsonDecode(jsonEncode(body.toJson())) as Map<String, dynamic>,
    );

    test('round-trips every kind of step, in order', () {
      const body = BatchBody(
        operations: [
          BatchOperation.create(
            CreateBody(table: 'orgs', object: {'id': 'o1'}),
          ),
          BatchOperation.createMany(
            CreateManyBody(
              table: 'members',
              objects: [
                {'id': 'm1'},
                {'id': 'm2'},
              ],
            ),
          ),
          BatchOperation.update(
            UpdateOneBody(
              table: 'orgs',
              where: Eq('id', 'o1'),
              updates: [
                ObjectUpdate({'owner_id': 'u2'}),
              ],
              expect: Eq('owner_id', 'u1'),
            ),
          ),
          BatchOperation.updateMany(
            UpdateBody(
              table: 'apps',
              where: Eq('owner_id', 'u1'),
              limit: 50,
              updates: [
                ObjectUpdate({'owner_id': 'u2'}),
              ],
            ),
          ),
          BatchOperation.delete(
            DeleteOneBody(table: 'members', where: Eq('id', 'm1')),
          ),
          BatchOperation.deleteMany(
            DeleteBody(table: 'invites', where: Eq('org_id', 'o1'), limit: 9),
          ),
        ],
      );

      final restored = roundTrip(body);

      expect(
        [for (final o in restored.operations) o.op],
        [
          'create',
          'createMany',
          'update',
          'updateMany',
          'delete',
          'deleteMany',
        ],
      );
      expect(
        [for (final o in restored.operations) o.table],
        ['orgs', 'members', 'orgs', 'apps', 'members', 'invites'],
      );

      final ops = restored.operations;
      final create = ops[0] as BatchCreate;
      final createMany = ops[1] as BatchCreateMany;
      final update = ops[2] as BatchUpdate;
      final updateMany = ops[3] as BatchUpdateMany;
      final delete = ops[4] as BatchDelete;
      final deleteMany = ops[5] as BatchDeleteMany;
      expect(create.body.object, {'id': 'o1'});
      expect(createMany.body.objects, hasLength(2));
      expect(update.body.limit, 1);
      expect(update.body.expect, isA<Eq>());
      expect(updateMany.body.limit, 50);
      expect(updateMany.body.expect, isNull);
      expect(delete.body.limit, 1);
      expect(deleteMany.body.limit, 9);
    });

    test('refuses an unknown op as an invalid body', () {
      expect(
        () => BatchBody.fromJson({
          'operations': [
            {'op': 'upsert', 'table': 't', 'object': <String, dynamic>{}},
          ],
        }),
        throwsA(
          isA<InvalidBodyException>().having(
            (e) => e.message,
            'message',
            contains('unknown op "upsert"'),
          ),
        ),
      );
    });

    test('refuses a step missing its fields as an invalid body', () {
      expect(
        () => BatchBody.fromJson({
          'operations': [
            {'op': 'update', 'table': 't'},
          ],
        }),
        throwsA(isA<InvalidBodyException>()),
      );
    });

    test('refuses more than maxOperations steps as an invalid body', () {
      expect(
        () => BatchBody.fromJson({
          'operations': [
            for (var i = 0; i <= BatchBody.maxOperations; i++)
              {'op': 'create', 'table': 't', 'object': <String, dynamic>{}},
          ],
        }),
        throwsA(
          isA<InvalidBodyException>().having(
            (e) => e.message,
            'message',
            contains('more than the ${BatchBody.maxOperations}'),
          ),
        ),
      );
    });

    test('refuses a body with no operations list as an invalid body', () {
      expect(
        () => BatchBody.fromJson({'ops': <Object?>[]}),
        throwsA(isA<InvalidBodyException>()),
      );
    });
  });

  group(BatchResult, () {
    test('round-trips', () {
      const result = BatchResult(
        op: 'update',
        table: 'orgs',
        count: 1,
        rows: [
          {'id': 'o1', 'owner_id': 'u2'},
        ],
      );

      final restored = BatchResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>,
      );

      expect(restored.op, 'update');
      expect(restored.table, 'orgs');
      expect(restored.count, 1);
      expect(restored.rows, [
        {'id': 'o1', 'owner_id': 'u2'},
      ]);
    });
  });
}
