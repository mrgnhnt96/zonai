import 'package:raindrop/raindrop.dart' hide Table;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/table_extensions.dart';

class _Rules {
  _Rules();

  BaseTableRules? tableRules;
  BaseRecordRules? record;
}

class DbRules {
  DbRules({required this.rules, this.dialect = const SQLiteDialect()});

  final List<Rules> rules;
  final BaseSqlDialect dialect;

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        RuleRequest request;
        try {
          request = RuleRequest.fromRequest(msg);
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
          case final TableRulesRequest request:
            return await _tableRules(request);
          case final RecordRulesRequest request:
            return await _recordRules(request);
          case final AuthTableRulesRequest request:
            return await _authTableRules(request);
          case final AuthRecordRulesRequest request:
            return await _authRecordRules(request);
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

  void _assertRecordRules(_Rules rules) {
    final record = rules.record;
    if (record == null) {
      return;
    }

    if (record case InternalRecordRules(canBeOverridden: true)) {
      return;
    }

    throw StateError(
      'Table rules already registered for ${record.table.name}',
    );
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

        case final RecordRules rule:
          _assertRecordRules(r);
          r.record = rule;
        case final AuthRecordRules rule:
          _assertRecordRules(r);
          r.record = rule;
      }
    }

    return _rulesByTable = rules;
  }

  Future<TableRulesResponse> _tableRules(
    TableRulesRequest request,
  ) async {
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
        '(only record rules may be registered).',
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

  Never _failAuthRecordRules(
    String table,
    _Rules? bucket,
    BaseRecordRules? recordRules,
  ) {
    final registered = rulesByTable.keys.toList()..sort();
    final buf = StringBuffer(
      'Auth record rules request for "$table" could not be handled.\n',
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
    } else if (recordRules == null) {
      buf.writeln(
        'Rules exist for "$table" but there are no record-level rules.',
      );
    } else {
      buf
        ..writeln(
          'Expected AuthRecordRules for "$table", but record rules are '
          '${recordRules.runtimeType} '
          '(schema: ${recordRules.schema.runtimeType}).',
        )
        ..writeln(
          'If you recently added both RecordRules and AuthRecordRules for the '
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

  Future<AuthRecordRulesResponse> _authRecordRules(
    AuthRecordRulesRequest request,
  ) async {
    final bucket = rulesByTable[request.table];
    final recordRules = bucket?.record;
    if (recordRules is AuthRecordRules) {
      return AuthRecordRulesResponse(
        id: request.id,
        table: request.table,
        canAccess: switch (request.operation) {
          .signIn => await recordRules.canSignIn(request.jwt, request.authType),
          .signUp => await recordRules.canSignUp(request.jwt, request.authType),
          .passwordReset => await recordRules.canPasswordReset(
            request.jwt,
            request.authType,
          ),
        },
        authType: request.authType,
        operation: request.operation,
      );
    }

    _failAuthRecordRules(request.table, bucket, recordRules);
  }

  Future<RecordRulesResponse> _recordRules(RecordRulesRequest request) async {
    final rules = rulesByTable[request.table];
    final recordRules = rules?.record;

    final op = request.operation;
    if (recordRules == null) {
      logger.warn('No rules found for record: ${request.table}');
      return RecordRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canPerform: false,
      );
    }

    if (recordRules case AuthRecordRules() when op == .create) {
      throw StateError('Cannot create auth records, use the auth API instead');
    }

    final object = recordRules.table.safeCreate(request.data);

    final canPerform = await switch (op) {
      .view => recordRules.canView(request.jwt, object),
      .update => recordRules.canUpdate(request.jwt, object),
      .delete => recordRules.canDelete(request.jwt, object),
      .create => recordRules.canCreate(request.jwt, object),
    };

    return RecordRulesResponse(
      id: request.id,
      table: request.table,
      operation: request.operation,
      canPerform: canPerform,
    );
  }
}
