import 'package:raindrop/raindrop.dart' hide Table;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/types/collection_actions.dart';

class _Rules {
  _Rules();

  BaseTableRules? tableRules;
  BaseRowRules? row;
}

class DbRules {
  DbRules({required this.rules, this.dialect = const SQLiteDialect()});

  final List<Rules> rules;
  final BaseSqlDialect dialect;

  void start() {
    MessageHandler(
      fromUnknownRequest: RuleRequest.fromRequest,
      onMessage: (request) async {
        switch (request) {
          case final TableRulesRequest request:
            return await _tableRules(request);
          case final RowRulesRequest request:
            return await _rowRules(request);
          case final AuthTableRulesRequest request:
            return await _authTableRules(request);
          case final AuthRowRulesRequest request:
            return await _authRowRules(request);
          case final GetAllTableCollectionActionsRequest request:
            return await _allTableCollectionActions(request);
        }
      },
    ).listen();
  }

  void _assertTableRules(_Rules rules) {
    final tableRules = rules.tableRules;
    if (tableRules == null) {
      return;
    }

    if (tableRules case InternalTableRules(canBeOverridden: true)) {
      return;
    }

    throw StateError(
      'Table rules already registered for ${tableRules.table.name}',
    );
  }

  void _assertRowRules(_Rules rules) {
    final row = rules.row;
    if (row == null) {
      return;
    }

    if (row case InternalRowRules(canBeOverridden: true)) {
      return;
    }

    throw StateError('Row rules already registered for ${row.table.name}');
  }

  Map<String, _Rules>? _rulesByTable;
  Map<String, _Rules> get rulesByTable {
    if (_rulesByTable case final rules?) return rules;

    final rules = <String, _Rules>{};
    for (final rule in this.rules) {
      final r = rules[rule.table.name] ??= _Rules();

      switch (rule) {
        case final TableRules rule:
          _assertTableRules(r);
          r.tableRules = rule;
        case final AuthTableRules rule:
          _assertTableRules(r);
          r.tableRules = rule;

        case final RowRules rule:
          _assertRowRules(r);
          r.row = rule;
        case final AuthRowRules rule:
          _assertRowRules(r);
          r.row = rule;
      }
    }

    return _rulesByTable = rules;
  }

  Future<TableRulesResponse> _tableRules(TableRulesRequest request) async {
    final rules = rulesByTable[request.table];
    final tableRules = rules?.tableRules;

    // TODO(future): We can support custom operations by forwarding
    // the request operation to the rules
    final op = request.classicOperation;
    if (op == null) {
      return TableRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canAccess: false,
      );
    }

    if (tableRules == null) {
      logger.warn('No rules found for table: ${request.table}');
      return TableRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canAccess: false,
      );
    }

    if (op == .create && tableRules is AuthTableRules) {
      throw StateError('Cannot create auth records, use the auth API instead');
    }

    final canAccess = await switch (op) {
      .create => tableRules.canCreate(request.jwt),
      .update => tableRules.canUpdate(request.jwt),
      .delete => tableRules.canDelete(request.jwt),
      .view => tableRules.canView(request.jwt),
      .list => tableRules.canList(request.jwt),
    };

    return TableRulesResponse(
      id: request.id,
      table: request.table,
      operation: request.operation,
      canAccess: canAccess,
    );
  }

  Future<AllTableCollectionActionsResponse> _allTableCollectionActions(
    GetAllTableCollectionActionsRequest request,
  ) async {
    final actions = <String, TableCollectionActions>{};
    for (final table in rulesByTable.keys) {
      final tableRules = rulesByTable[table]?.tableRules;
      if (tableRules == null) {
        actions[table] = TableCollectionActions.denied(table);
        continue;
      }

      actions[table] = TableCollectionActions(
        table: table,
        canCreate: await tableRules.canCreate(request.jwt),
        canUpdate: await tableRules.canUpdate(request.jwt),
        canDelete: await tableRules.canDelete(request.jwt),
      );
    }

    return AllTableCollectionActionsResponse(id: request.id, actions: actions);
  }

  Never _failAuthTableRules(
    String table,
    _Rules? bucket,
    BaseTableRules? tableRules,
  ) {
    final registered = rulesByTable.keys.toList()..sort();
    final buf = StringBuffer(
      'Auth table rules request for "$table" could not be handled.\n',
    );
    if (bucket == null) {
      buf
        ..writeln(
          'No rules are registered for table name "$table". '
          'The rules list may be missing this table (e.g. loadRule failed, '
          'or main() did not return Rules).',
        )
        ..writeln(
          'Registered table names: '
          '${registered.isEmpty ? '(none)' : registered.join(', ')}.',
        );
    } else if (tableRules == null) {
      buf.writeln(
        'Rules exist for "$table" but there are no table-level rules '
        '(only row rules may be registered).',
      );
    } else {
      buf
        ..writeln(
          'Expected AuthTableRules for "$table", but table rules '
          'are ${tableRules.runtimeType} '
          '(schema: ${tableRules.schema.runtimeType}).',
        )
        ..writeln(
          'If you recently added both TableRules and AuthTableRules '
          'for the same table, note that the last registration wins when '
          'building the rules map.',
        );
    }
    final message = buf.toString().trim();
    logger.error(message);
    throw StateError(message);
  }

  Never _failAuthRowRules(
    String table,
    _Rules? bucket,
    BaseRowRules? rowRules,
  ) {
    final registered = rulesByTable.keys.toList()..sort();
    final buf = StringBuffer(
      'Auth row rules request for "$table" could not be handled.\n',
    );
    if (bucket == null) {
      buf
        ..writeln(
          'No rules are registered for table name "$table". '
          'The rules list may be missing this table (e.g. loadRule failed, '
          'or main() did not return Rules).',
        )
        ..writeln(
          'Registered table names: '
          '${registered.isEmpty ? '(none)' : registered.join(', ')}.',
        );
    } else if (rowRules == null) {
      buf.writeln('Rules exist for "$table" but there are no row-level rules.');
    } else {
      buf
        ..writeln(
          'Expected AuthRowRules for "$table", but row rules are '
          '${rowRules.runtimeType} '
          '(schema: ${rowRules.schema.runtimeType}).',
        )
        ..writeln(
          'If you recently added both RowRules and AuthRowRules for the '
          'same table, note that the last registration wins when building the '
          'rules map.',
        );
    }
    final message = buf.toString().trim();
    logger.error(message);
    throw StateError(message);
  }

  Future<AuthTableRulesResponse> _authTableRules(
    AuthTableRulesRequest request,
  ) async {
    final bucket = rulesByTable[request.table];
    final tableRules = bucket?.tableRules;
    if (tableRules is AuthTableRules) {
      return AuthTableRulesResponse(
        id: request.id,
        table: request.table,
        canAuthenticate: await tableRules.canAuthenticate(
          request.jwt,
          request.authType,
        ),
        authType: request.authType,
      );
    }

    _failAuthTableRules(request.table, bucket, tableRules);
  }

  Future<AuthRowRulesResponse> _authRowRules(
    AuthRowRulesRequest request,
  ) async {
    final bucket = rulesByTable[request.table];
    final rowRules = bucket?.row;
    if (rowRules is AuthRowRules) {
      return AuthRowRulesResponse(
        id: request.id,
        table: request.table,
        canAccess: switch (request.operation) {
          .signIn => await rowRules.canSignIn(request.jwt, request.authType),
          .signUp => await rowRules.canSignUp(request.jwt, request.authType),
          .passwordReset => await rowRules.canPasswordReset(
            request.jwt,
            request.authType,
          ),
        },
        authType: request.authType,
        operation: request.operation,
      );
    }

    _failAuthRowRules(request.table, bucket, rowRules);
  }

  Future<RowRulesResponse> _rowRules(RowRulesRequest request) async {
    final rules = rulesByTable[request.table];
    final rowRules = rules?.row;

    final op = request.operation;
    if (rowRules == null) {
      logger.warn('No rules found for row: ${request.table}');
      return RowRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canPerform: false,
      );
    }

    if (rowRules case AuthRowRules() when op == .create) {
      throw StateError('Cannot create auth rows, use the auth API instead');
    }

    final object = rowRules.table.safeCreate(request.data);

    final canPerform = await switch (op) {
      .view => rowRules.canView(request.jwt, object),
      .update => rowRules.canUpdate(request.jwt, object),
      .delete => rowRules.canDelete(request.jwt, object),
      .create => rowRules.canCreate(request.jwt, object),
    };

    return RowRulesResponse(
      id: request.id,
      table: request.table,
      operation: request.operation,
      canPerform: canPerform,
    );
  }
}
