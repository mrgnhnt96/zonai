import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbOperations {
  DbOperations({
    required this.operations,
    this.dialect = const SQLiteDialect(),
  });

  final List<CollectionOperations> operations;
  final BaseSqlDialect dialect;

  Map<String, CollectionOperations>? _operationsByCollection;
  Map<String, CollectionOperations> get operationsByCollection {
    return _operationsByCollection ??= {
      for (final operation in this.operations) operation.table.name: operation,
    };
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
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling operation request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        switch (request) {
          case final PerformOperationRequest request:
            return await _performOperation(request);
          case final ViewAuthOperationRequest request:
            return await _viewAuthOperation(request);
          case final CreateAuthOperationRequest request:
            return await _createAuthOperation(request);
          case final GetPasswordColumnNameRequest request:
            return await _getPasswordColumnName(request);
        }
      },
    ).listen();
  }

  Future<PasswordColumnNameResponse> _getPasswordColumnName(
    GetPasswordColumnNameRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      throw Exception('Collection not found: ${request.collection}');
    }

    final passwordColumn = collection.table.columns.firstWhere(
      (column) => column.transformer is PasswordTransformer,
    );

    return PasswordColumnNameResponse(
      id: request.id,
      columnName: passwordColumn.name,
    );
  }

  Future<PerformOperationResponse> _createAuthOperation(
    CreateAuthOperationRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      throw Exception('Collection not found: ${request.collection}');
    }

    final emailColumn = switch (request.payload.authType) {
      .password => collection.table.columns.firstWhere(
        (column) => column.transformer is EmailTransformer,
      ),
    };

    final passwordColumn = switch (request.payload.authType) {
      .password => collection.table.columns.firstWhere(
        (column) => column.transformer is PasswordTransformer,
      ),
    };

    final email = switch (request.payload) {
      PasswordAuthOperationPayload(:final email) => email,
    };

    final passwordHash = switch (request.payload) {
      PasswordAuthOperationPayload(:final passwordHash) => passwordHash,
    };

    final otherFields = switch (request.payload) {
      PasswordAuthOperationPayload(:final object) => object,
    };

    final operationRequest = CreateOperationRequest(
      collection: request.collection,
      object: {
        ...?otherFields,
        emailColumn.name: email,
        passwordColumn.name: passwordHash,
      },
    );

    final (sql, values) = CollectionTranslator(
      collection,
      dialect,
    ).translate(operationRequest);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<PerformOperationResponse> _viewAuthOperation(
    ViewAuthOperationRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      throw Exception('Collection not found: ${request.collection}');
    }

    final table = collection.table;

    final emailColumn = switch (request.payload.authType) {
      .password => table.columns.firstWhere(
        (column) => column.transformer is EmailTransformer,
      ),
    };

    final email = switch (request.payload) {
      PasswordAuthOperationPayload(:final email) => email,
    };

    final operationRequest = ViewOperationRequest(
      collection: request.collection,
      where: '"${emailColumn.name}" = \'${email}\'',
    );

    final (sql, values) = CollectionTranslator(
      collection,
      dialect,
    ).translate(operationRequest);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<PerformOperationResponse> _performOperation(
    PerformOperationRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      // TODO(mrgnhnt): Get the operations directory from the settings
      final operationsDir = '__TODO__GET_OPERATIONS_DIR__';
      throw Exception('''
    Missing operations for collection: `${request.collection}`

    Available collections:
    ${operationsByCollection.keys.join('\n')}

    To create a new collection, create a new class that extends `CollectionOperations` within your $operationsDir directory.
    ''');
    }

    final (sql, values) = CollectionTranslator(
      collection,
      dialect,
    ).translate(request);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }
}
