import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

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
        OperationRequest request;
        try {
          request = OperationRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.error(
            'Error handling operation request',
            error: '$e',
            stackTrace: stack.toString(),
            properties: {'request': msg.toJson()},
          );
          return null;
        }

        switch (request) {
          case final PerformOperationRequest request:
            return await _performOperation(request);
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

    final (sql, values) = CollectionTranslator(
      collection,
      dialect,
    ).translate(request);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }
}
