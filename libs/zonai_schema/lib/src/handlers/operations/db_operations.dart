import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';
import 'package:zonai_schema/zonai_schema.dart' hide Table;

class DbOperations {
  DbOperations({
    required this.operations,
    required this.tables,
    this.dialect = const SQLiteDialect(),
  });

  final List<TableOperations> operations;
  final List<rd.Schema> tables;
  final SqlDialect dialect;

  Map<String, TableOperations>? _operationsByTable;
  Map<String, TableOperations> get operationsByTable {
    if (_operationsByTable case final map?) return map;

    final map = <String, TableOperations>{};
    for (final operation in this.operations) {
      if (map[operation.table.name] != null) {
        throw StateError(
          'Operations already registered for ${operation.table.name}. '
          'Existing operations: ${map[operation.table.name]?.runtimeType}, tried to register ${operation.runtimeType}',
        );
      }

      map[operation.table.name] = operation;
    }

    for (final schema in tables) {
      final name = schema.$.name;
      map.putIfAbsent(name, () => defaultOperationsFor(schema));
    }

    return _operationsByTable = map;
  }

  void start({MessageIo? io}) {
    MessageHandler(
      fromUnknownRequest: OperationRequest.fromRequest,
      onMessage: dispatch,
      io: io,
    ).listen();
  }

  /// Handles one ops request without any transport. Used by stdio workers,
  /// SendPort isolates, and in-process project binaries.
  Future<Response?> dispatch(OperationRequest request) async {
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
      case final GetColumnReferenceRequest request:
        return await _getColumnReference(request);
      case final GetAllTableSchemaShapesRequest request:
        return await _getAllTableSchemaShapes(request);
      case final GetJwtConfigOperationRequest request:
        return await _getJwtConfig(request);
      case final SanitizeOperationRequest request:
        return await _sanitize(request);
      case final GetAdminTablesOperationRequest request:
        return await _getAdminTables(request);
      case final GetMagicLinkConfigOperationRequest request:
        return await _getMagicLinkConfig(request);
      case final GetResetPasswordConfigOperationRequest request:
        return await _getResetPasswordConfig(request);
      case final GetVerifyEmailConfigOperationRequest request:
        return await _getVerifyEmailConfig(request);
    }
  }

  Future<AdminTablesResponse> _getAdminTables(
    GetAdminTablesOperationRequest request,
  ) async {
    final tables = <(String, List<AuthType>)>[];
    for (final op in operationsByTable.values) {
      if ((op.schema, op.schema) case (final AuthTable ops, AsAdmin())) {
        tables.add((op.table.name, ops.authTypes));
      }
    }

    return AdminTablesResponse(id: request.id, tables: tables);
  }

  Never _failMissingTable(String tableName) {
    final registered = operationsByTable.keys.toList()..sort();
    logger.error(
      'Operations request for "$tableName" could not be handled. '
      'Registered table names: '
      '${registered.isEmpty ? '(none)' : registered.join(', ')}.',
    );
    throw TableNotRegisteredException(table: tableName);
  }

  Future<ColumnNameResponse> _getColumnName(
    GetColumnNameRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final column = switch (request.columnName) {
      .password => _passwordColumn(ops.table, tableName: request.table),
      .isVerified => _isVerifiedColumn(ops.table, tableName: request.table),
      .email => _emailColumn(ops.table, tableName: request.table),
      .id => _idColumn(ops.table, tableName: request.table),
    };

    if (column == null) {
      return ColumnNameResponse(
        id: request.id,
        name: null,
        column: request.columnName,
      );
    }

    return ColumnNameResponse(
      id: request.id,
      name: column.name,
      column: request.columnName,
    );
  }

  Future<AllTableSchemaShapesResponse> _getAllTableSchemaShapes(
    GetAllTableSchemaShapesRequest request,
  ) async {
    final shapes = <String, TableSchemaShape>{};
    for (final name in operationsByTable.keys) {
      final ops = operationsByTable[name]!;
      shapes[name] = tableSchemaShapeFromTable(
        ops.table,
        isView: ops is ViewOperations,
      );
    }
    return AllTableSchemaShapesResponse(id: request.id, shapes: shapes);
  }

  Future<ColumnReferenceResponse> _getColumnReference(
    GetColumnReferenceRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    rd.Column<dynamic, dynamic>? column;
    for (final candidate in ops.table.columns) {
      if (candidate.name == request.columnName) {
        column = candidate;
        break;
      }
    }
    if (column == null) {
      throw ColumnNotFoundException(
        table: request.table,
        columnName: request.columnName,
      );
    }

    final fkRef = column.foreignKeyReference;

    return ColumnReferenceResponse(
      id: request.id,
      columnName: column.name,
      referencedTable: fkRef?.referencedTable,
      referencedColumn: fkRef?.referencedColumnName,
    );
  }

  Future<PerformOperationResponse> _createAuthOperation(
    CreateAuthOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final emailColumn = _emailColumn(ops.table, tableName: request.table);

    final email = switch (request.payload) {
      PasswordAuthOperationPayload(:final email) => email,
      OtpAuthOperationPayload(:final email) => email,
      MagicLinkAuthOperationPayload(:final email) => email,
    };

    final otherFields = switch (request.payload) {
      PasswordAuthOperationPayload(:final object) => object,
      OtpAuthOperationPayload(:final object) => object,
      MagicLinkAuthOperationPayload(:final object) => object,
    };

    rd.Column? passwordColumn;
    if (ops.schema is PasswordAuth) {
      passwordColumn = _passwordColumn(ops.table, tableName: request.table);
    }

    rd.Column? isVerifiedColumn;
    if (ops.schema is HasEmail) {
      isVerifiedColumn = _isVerifiedColumn(ops.table, tableName: request.table);
    }

    if (emailColumn == null) {
      throw StateError('No email column on table "${request.table}"');
    }

    final object = switch (request.payload) {
      PasswordAuthOperationPayload(:final passwordHash) => {
        ...?otherFields,
        emailColumn.name: email,
        if (passwordColumn != null) passwordColumn.name: passwordHash,
        if (isVerifiedColumn != null) isVerifiedColumn.name: false,
      },
      OtpAuthOperationPayload() => {
        ...?otherFields,
        emailColumn.name: email,
        if (isVerifiedColumn != null)
          isVerifiedColumn.name: true
        else
          '': throw StateError('Is verified column is required'),
        // provide empty password hash to comply
        if (passwordColumn != null && !passwordColumn.isNullable)
          passwordColumn.name: '',
      },
      MagicLinkAuthOperationPayload() => {
        ...?otherFields,
        emailColumn.name: email,
        if (isVerifiedColumn != null)
          isVerifiedColumn.name: true
        else
          '': throw StateError('Is verified column is required'),
        // provide empty password hash to comply
        if (passwordColumn != null && !passwordColumn.isNullable)
          passwordColumn.name: '',
      },
    };

    final operationRequest = CreateOperationRequest(
      table: request.table,
      object: object,
      jwt: request.jwt,
    );

    final (sql, values) = TableTranslator(
      ops,
      dialect,
    ).translate(operationRequest);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<PerformOperationResponse> _viewAuthOperation(
    ViewAuthOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final table = ops.table;

    final emailColumn = _emailColumn(table, tableName: request.table);

    if (emailColumn == null) {
      throw StateError('No email column on table "${request.table}"');
    }

    final email = switch (request.payload) {
      PasswordAuthOperationPayload(:final email) => email,
      OtpAuthOperationPayload(:final email) => email,
      MagicLinkAuthOperationPayload(:final email) => email,
    };

    final operationRequest = ReadOperationRequest(
      table: request.table,
      where: Eq(emailColumn.name, email),
      jwt: request.jwt,
    );

    final (sql, values) = TableTranslator(
      ops,
      dialect,
    ).translate(operationRequest);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<PerformOperationResponse> _performOperation(
    PerformOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final (sql, values) = TableTranslator(ops, dialect).translate(request);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<PerformOperationResponse> _count(CountOperationRequest request) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final (sql, values) = TableTranslator(ops, dialect).translate(request);

    return PerformOperationResponse(id: request.id, query: sql, values: values);
  }

  Future<SanitizeOperationResponse> _sanitize(
    SanitizeOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final columns = ops.table.columns;
    final photoColumns = <String>[];
    final secretColumns = <String>[];
    for (final column in columns) {
      switch (column.transformer) {
        case PhotoTransformer():
          photoColumns.add(column.name);
        case PhotosTransformer():
          photoColumns.add(column.name);
        case SecretTransformer():
          secretColumns.add(column.name);
        case _:
      }
    }
    final sanitized = <Map<String, dynamic>>[];
    for (final raw in request.objects) {
      final mutable = {...raw};
      if (!request.preserveSecrets) {
        for (final name in secretColumns) {
          mutable.remove(name);
        }
      }
      sanitized.add(mutable);
    }

    return SanitizeOperationResponse(
      id: request.id,
      objects: sanitized,
      photoColumns: photoColumns,
      secretColumns: secretColumns,
    );
  }

  Future<JwtConfigResponse> _getJwtConfig(
    GetJwtConfigOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    final claims = switch (ops) {
      AuthOperations(:final addClaims) => await addClaims(jwt: request.jwt),
      _ => Claims(const {}),
    };

    final expiresIn = switch (ops) {
      AuthOperations(:final jwtExpiresIn) => jwtExpiresIn,
      _ => null,
    };

    final admin = switch (ops?.schema) {
      final AsAdmin admin => admin,
      _ => null,
    };

    return JwtConfigResponse(
      id: request.id,
      config: JwtConfig(
        claims: claims,
        isAdmin: admin != null,
        canEdit: admin?.canEdit ?? false,
        expiresIn: expiresIn,
      ),
    );
  }

  Future<MagicLinkConfigResponse> _getMagicLinkConfig(
    GetMagicLinkConfigOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }
    final config = switch (ops) {
      AuthOperations(:final magicLinkConfig) => await magicLinkConfig(),
      _ => throw StateError('Table does not support magic link'),
    };

    return MagicLinkConfigResponse(id: request.id, config: config);
  }

  Future<ResetPasswordConfigResponse> _getResetPasswordConfig(
    GetResetPasswordConfigOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }
    final config = switch (ops) {
      AuthOperations(:final resetPasswordConfig) => await resetPasswordConfig(),
      _ => throw StateError('Table does not support reset password'),
    };

    return ResetPasswordConfigResponse(id: request.id, config: config);
  }

  Future<VerifyEmailConfigResponse> _getVerifyEmailConfig(
    GetVerifyEmailConfigOperationRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }
    final config = switch (ops) {
      AuthOperations(:final verifyEmailConfig) => await verifyEmailConfig(),
      _ => throw StateError('Table does not support verify email'),
    };

    return VerifyEmailConfigResponse(id: request.id, config: config);
  }

  rd.Column? _tryFindColumn(
    rd.TableMeta table,
    bool Function(rd.Column<dynamic, dynamic> column) test,
  ) {
    for (final column in table.columns) {
      if (test(column)) {
        return column;
      }
    }
    return null;
  }

  rd.Column? _emailColumn(rd.TableMeta table, {required String tableName}) {
    return _tryFindColumn(
      table,
      (column) => column.transformer is EmailTransformer,
    );
  }

  rd.Column? _isVerifiedColumn(
    rd.TableMeta table, {
    required String tableName,
  }) {
    return _tryFindColumn(
      table,
      (column) => column.transformer is IsVerifiedTransformer,
    );
  }

  rd.Column? _passwordColumn(rd.TableMeta table, {required String tableName}) {
    return _tryFindColumn(
      table,
      (column) => column.transformer is PasswordTransformer,
    );
  }

  rd.Column _idColumn(rd.TableMeta table, {required String tableName}) {
    return _tryFindColumn(
          table,
          (column) =>
              column.transformer is IdTransformer && column.isPrimaryKey,
        ) ??
        (throw StateError('No id column on table "$tableName"'));
  }
}
