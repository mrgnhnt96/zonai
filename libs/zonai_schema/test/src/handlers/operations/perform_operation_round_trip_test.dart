import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;

/// A worker receives every operation request as an [UnknownRequest] and
/// rebuilds it with [OperationRequest.fromRequest]. A request that does not
/// come back as its own type fails in the worker, and the caller sees a 500.
///
/// That is what happened to `POST /db/many`: [CreateManyOperationRequest]
/// travels with `operation: 'create'`, the same as a single create, so it was
/// rebuilt as a [CreateOperationRequest], which then read the absent `object`.
void main() {
  OperationRequest overTheWire(OperationRequest request) {
    final onTheWire = Request.fromJson(request.toJson());
    expect(
      onTheWire,
      isA<UnknownRequest>(),
      reason: 'a worker receives every operation request as an UnknownRequest',
    );
    return OperationRequest.fromRequest(onTheWire as UnknownRequest);
  }

  test('a create-many comes back as a create-many, with every row', () {
    final decoded = overTheWire(
      CreateManyOperationRequest(
        table: 'widgets',
        objects: [
          {'code': '1'},
          {'code': '2'},
        ],
        jwt: null,
      ),
    );

    expect(decoded, isA<CreateManyOperationRequest>());
    expect((decoded as CreateManyOperationRequest).table, 'widgets');
    expect(decoded.objects, [
      {'code': '1'},
      {'code': '2'},
    ]);
    expect(decoded.classicOperation, TableOperation.create);
  });

  test('a single create still comes back as a single create', () {
    final decoded = overTheWire(
      CreateOperationRequest(
        table: 'widgets',
        object: {'code': '1'},
        jwt: null,
      ),
    );

    expect(decoded, isA<CreateOperationRequest>());
    expect((decoded as CreateOperationRequest).object, {'code': '1'});
  });

  test('a create-many with no rows is still a create-many', () {
    final decoded = overTheWire(
      CreateManyOperationRequest(table: 'widgets', objects: [], jwt: null),
    );

    expect(decoded, isA<CreateManyOperationRequest>());
    expect((decoded as CreateManyOperationRequest).objects, isEmpty);
  });
}
