import 'package:raindrop/raindrop.dart' as rd;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
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
  final rd.BaseSqlDialect dialect;

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
      final name = rd.Table.getFor(schema).name;
      map.putIfAbsent(name, () => defaultOperationsFor(schema));
    }

    return _operationsByTable = map;
  }

  void start() {
    MessageHandler(
      fromUnknownRequest: OperationRequest.fromRequest,
      onMessage: (request) async {
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
      },
    ).listen();
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
    final buf = StringBuffer(
      'Operations request for "$tableName" could not be handled.\n',
    );
    buf
      ..writeln(
        'No operations are registered for table name "$tableName". '
        'The operations list may be missing this table (e.g. loadOperation '
        'failed, or main() did not return TableOperations).',
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
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final column = switch (request.columnName) {
      .password => _passwordColumn(ops.table),
      .isVerified => _isVerifiedColumn(ops.table),
      .email => _emailColumn(ops.table),
      .id => _idColumn(ops.table),
    };

    return ColumnNameResponse(
      id: request.id,
      name: column.name,
      column: request.columnName,
    );
  }

  Future<ColumnReferenceResponse> _getColumnReference(
    GetColumnReferenceRequest request,
  ) async {
    final ops = operationsByTable[request.table];
    if (ops == null) {
      _failMissingTable(request.table);
    }

    final column = ops.table.columns.firstWhere(
      (c) => c.name == request.columnName,
      orElse: () => throw StateError(
        'Column "${request.columnName}" not found on "${request.table}"',
      ),
    );

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

    final emailColumn = _emailColumn(ops.table);

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
      passwordColumn = _passwordColumn(ops.table);
    }

    rd.Column? isVerifiedColumn;
    if (ops.schema is HasEmail) {
      isVerifiedColumn = _isVerifiedColumn(ops.table);
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

    final emailColumn = _emailColumn(table);

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
    for (final column in columns) {
      switch (column.transformer) {
        case PhotoTransformer():
          photoColumns.add(column.name);
        case PhotosTransformer():
          photoColumns.add(column.name);
        case _:
      }
    }
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

    return SanitizeOperationResponse(
      id: request.id,
      objects: sanitized,
      photoColumns: photoColumns,
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

  rd.Column _emailColumn(rd.Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is EmailTransformer,
    );
  }

  rd.Column _isVerifiedColumn(rd.Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is IsVerifiedTransformer,
    );
  }

  rd.Column _passwordColumn(rd.Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is PasswordTransformer,
    );
  }

  rd.Column _idColumn(rd.Table table) {
    return table.columns.firstWhere(
      (column) => column.transformer is IdTransformer && column.isPrimaryKey,
    );
  }
}
