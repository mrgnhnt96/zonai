import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';
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
          logger.debug(
            'Error handling request',
            properties: {'request': msg.toJson(), 'error': e.toString()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        switch (request) {
          case final CountOperationRequest request:
            return await _count(request);
          case final PerformOperationRequest request:
            return await _performOperation(request);
          case final ViewAuthOperationRequest request:
            return await _viewAuthOperation(request);
          case final CreateAuthOperationRequest request:
            return await _createAuthOperation(request);
          case final GetColumnNameRequest request:
            return await _getColumnName(request);
          case final GetClaimsOperationRequest request:
            return await _getClaims(request);
          case final SanitizeOperationRequest request:
            return await _sanitize(request);
          case final GetAdminCollectionsOperationRequest request:
            return await _getAdminCollections(request);
        }
      },
    ).listen();
  }

  Future<AdminCollectionsResponse> _getAdminCollections(
    GetAdminCollectionsOperationRequest request,
  ) async {
    final collections = <(String, List<AuthType>)>[];
    for (final op in operations) {
      if ((op.schema, op.schema) case (
        final AuthCollection collection,
        AsAdmin(),
      )) {
        collections.add((op.table.name, collection.authTypes));
      }
    }

    return AdminCollectionsResponse(id: request.id, collections: collections);
  }

  Never _failMissingCollection(String collection) {
    final registered = operationsByCollection.keys.toList()..sort();
    final buf = StringBuffer(
      'Operations request for "$collection" could not be handled.\n',
    );
    buf
      ..writeln(
        'No operations are registered for table name "$collection". '
        'The operations list may be missing this collection (e.g. loadOperation '
        'failed, or main() did not return CollectionOperations).',
      )
      ..writeln(
        'Registered table names: '
        '${registered.isEmpty ? '(none)' : registered.join(', ')}.',
      );

    final message = buf.toString().trim();
    logger.error(message);
    throw StateError(message);
  }

  Future<ColumnNameResponse> _getColumnName(
    GetColumnNameRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      _failMissingCollection(request.collection);
    }

    final column = switch (request.columnName) {
      .password => _passwordColumn(collection.table),
      .isVerified => _isVerifiedColumn(collection.table),
      .email => _emailColumn(collection.table),
      .id => _idColumn(collection.table),
    };

    return ColumnNameResponse(
      id: request.id,
      name: column.name,
      column: request.columnName,
    );
  }

  Future<PerformOperationResponse> _createAuthOperation(
    CreateAuthOperationRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      _failMissingCollection(request.collection);
    }

    final emailColumn = _emailColumn(collection.table);

    final email = switch (request.payload) {
      PasswordAuthOperationPayload(:final email) => email,
      OtpAuthOperationPayload(:final email) => email,
    };

    final otherFields = switch (request.payload) {
      PasswordAuthOperationPayload(:final object) => object,
      OtpAuthOperationPayload(:final object) => object,
    };

    Column? passwordColumn;
    if (collection.schema is PasswordAuth) {
      passwordColumn = _passwordColumn(collection.table);
    }

    Column? isVerifiedColumn;
    if (collection.schema is HasEmail) {
      isVerifiedColumn = _isVerifiedColumn(collection.table);
    }

    final object = switch (request.payload) {
      PasswordAuthOperationPayload(:final passwordHash) => {
        ...?otherFields,
        emailColumn.name: email,
        if (passwordColumn != null) passwordColumn.name: passwordHash,
      },
      OtpAuthOperationPayload() => {
        ...?otherFields,
        emailColumn.name: email,
        if (isVerifiedColumn != null) isVerifiedColumn.name: true,
        // provide empty password hash to comply
        if (passwordColumn != null && !passwordColumn.isNullable)
          passwordColumn.name: '',
      },
    };

    final operationRequest = CreateOperationRequest(
      collection: request.collection,
      object: object,
      jwt: request.jwt,
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
      _failMissingCollection(request.collection);
    }

    final table = collection.table;

    final emailColumn = _emailColumn(table);

    final email = switch (request.payload) {
      PasswordAuthOperationPayload(:final email) => email,
      OtpAuthOperationPayload(:final email) => email,
    };

    final operationRequest = ReadOperationRequest(
      collection: request.collection,
      where: Eq(emailColumn.name, email),
      jwt: request.jwt,
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
      _failMissingCollection(request.collection);
    }

    final (sql, values) = CollectionTranslator(
      collection,
      dialect,
    ).translate(request);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<PerformOperationResponse> _count(CountOperationRequest request) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      _failMissingCollection(request.collection);
    }

    final (sql, values) = CollectionTranslator(
      collection,
      dialect,
    ).translate(request);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<SanitizeOperationResponse> _sanitize(
    SanitizeOperationRequest request,
  ) async {
    final collection = operationsByCollection[request.collection];
    if (collection == null) {
      _failMissingCollection(request.collection);
    }

    final columns = collection.table.columns;
    final sanitized = <Map<String, dynamic>>[];
    for (final raw in request.objects) {
      final mutable = {...raw};
      for (final column in columns) {
        if (column.transformer is SecretTransformer) {
          mutable.remove(column.name);
        }
      }
      sanitized.add(mutable);
    }

    return SanitizeOperationResponse(id: request.id, objects: sanitized);
  }

  Future<ClaimsResponse> _getClaims(GetClaimsOperationRequest request) async {
    final collection = operationsByCollection[request.collection];
    final claims = switch (collection) {
      AuthOperations(:final addClaims) => await addClaims(jwt: request.jwt),
      _ => Claims(const {}),
    };

    final admin = switch (collection?.schema) {
      final AsAdmin admin => admin,
      _ => null,
    };

    return ClaimsResponse(
      id: request.id,
      claims: claims,
      isAdmin: admin != null,
      canEdit: admin?.canEdit ?? false,
    );
  }

  Column _emailColumn(Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is EmailTransformer,
    );
  }

  Column _isVerifiedColumn(Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is IsVerifiedTransformer,
    );
  }

  Column _passwordColumn(Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is PasswordTransformer,
    );
  }

  Column _idColumn(Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is IdTransformer && column.isPrimaryKey,
    );
  }
}
