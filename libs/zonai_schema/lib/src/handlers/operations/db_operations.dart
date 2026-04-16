import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_requests.dart';
import 'package:zonai_schema/src/handlers/operations/operation_responses.dart';
import 'package:zonai_schema/zonai_schema.dart' hide Request;

class DbOperations {
  DbOperations({
    required this.operations,
    this.dialect = const SQLiteDialect(),
  });

  final List<CollectionOperations> operations;
  final BaseSqlDialect dialect;

  Map<String, CollectionOperations>? _operationsByCollection;
  Map<String, CollectionOperations> get operationsByCollection {
    if (_operationsByCollection case final operations?) return operations;
    final operations = <String, CollectionOperations>{};
    for (final operation in this.operations) {
      operations[operation.table.name] = operation;
    }
    return _operationsByCollection = operations;
  }

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        final request = OperationRequest.fromRequest(msg);
        switch (request) {
          case final PerformOperationRequest request:
            return _performOperation(request);
        }
      },
    ).listen();
  }

  Future<PerformOperationResponse> _performOperation(
    PerformOperationRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      throw Exception('Collection not found: ${request.collection}');
    }

    final builder = switch (request) {
      CreateOperationRequest(:final object) => collection.insert(
        collection.table.create(object),
      ),
      UpdateOperationRequest(
        :final where,
        :final recordFilter,
        :final updates,
      ) =>
        collection.update(updates, where: where & recordFilter),
      DeleteOperationRequest(:final where, :final limit, :final recordFilter) =>
        collection.delete(where & recordFilter, limit: limit ?? 1),
      ViewOperationRequest(:final recordFilter) => collection.search(
        limit: 1,
        where: recordFilter,
      ),
      ListOperationRequest(:final limit, :final offset, :final recordFilter) =>
        collection.search(limit: limit, offset: offset, where: recordFilter),
      SearchOperationRequest(
        :final limit,
        :final offset,
        :final recordFilter,
        :final where,
      ) =>
        collection.search(
          limit: limit,
          offset: offset,
          where: where & recordFilter,
        ),
      CustomOperationRequest(
        :final operation,
        :final recordFilter,
        :final values,
      ) =>
        collection.custom(operation, where: recordFilter, values: values),
      PerformOperationRequest(:final operation) => throw StateError(
        'Invalid operation: $operation',
      ),
    };

    final raindropQuery = builder.toQuery();

    // `operationsByCollection` erases the schema type, so `toQuery()` is
    // `Query<Schema<dynamic>, …>` and `translate<S>` cannot infer `S extends Schema<S>`.
    final (sql, values) = dialect.translate<Never, Object?>(
      raindropQuery as Query<Never, Object?>,
    );

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }
}
