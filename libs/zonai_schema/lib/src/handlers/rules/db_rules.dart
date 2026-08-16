import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/provisioning_jwt.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/types/collection_actions.dart';
import 'package:zonai_schema/src/update/update.dart';
import 'package:zonai_schema/src/update/update_simulator.dart';

class _Rules {
  _Rules();

  BaseTableRules? tableRules;
  BaseRowRules? row;
}

class DbRules {
  DbRules({required this.rules, this.dialect = const SQLiteDialect()});

  final List<Rules> rules;
  final SqlDialect dialect;

  void start({MessageIo? io}) {
    MessageHandler(
      fromUnknownRequest: RuleRequest.fromRequest,
      onMessage: dispatch,
      io: io,
    ).listen();
  }

  /// Handles one rules request without any transport.
  Future<Response?> dispatch(RuleRequest request) async {
    switch (request) {
      case final TableRulesRequest request:
        return await _tableRules(request);
      case final RowRulesRequest request:
        return await _rowRules(request);
      case final BatchRowRulesRequest request:
        return await _batchRowRules(request);
      case final AuthTableRulesRequest request:
        return await _authTableRules(request);
      case final AuthRowRulesRequest request:
        return await _authRowRules(request);
      case final GetAllTableCollectionActionsRequest request:
        return await _allTableCollectionActions(request);
    }
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

    for (final MapEntry(key: table, value: bucket) in rules.entries) {
      _assertNoClassicNameCollision(table, bucket);
    }

    return _rulesByTable = rules;
  }

  /// Refuses a `customOperations` entry named after a classic verb.
  ///
  /// [RuleRequest.classicOperation] resolves an operation name to the built-in
  /// [TableOperation]/[RowOperation] whenever one matches, and both [_tableRules]
  /// and [_rowRules] branch on that first. So a rule registered under
  /// `customOperations['update']` is never reached — `canUpdate` decides the
  /// call instead — and nothing said so: the author reads a rule that is in the
  /// map, is never consulted, and denies nothing.
  ///
  /// Raised at map-construction time rather than per request, so it surfaces
  /// when the worker starts rather than on the first call that needed it.
  void _assertNoClassicNameCollision(String table, _Rules bucket) {
    final names = <String>{
      ...?bucket.tableRules?.customOperations.keys,
      ...?bucket.row?.customOperationNames,
    };

    for (final name in names) {
      if (TableOperation.fromString(name) != null ||
          RowOperation.fromString(name) != null) {
        throw CustomOperationNameCollisionException(
          table: table,
          operation: name,
        );
      }
    }
  }

  /// Registered custom operation names for [table]'s table-level rules —
  /// the same source of truth [_tableRules] denies against for an unknown
  /// name. Used to validate a custom operation before it reaches the rate
  /// limiter (bucketing on an unvalidated caller-supplied name would let a
  /// caller rotate it to dodge the limit entirely).
  Set<String> customTableOperationNames(String table) =>
      rulesByTable[table]?.tableRules?.customOperations.keys.toSet() ??
      const {};

  /// Registered custom operation names for [table]'s row-level rules. See
  /// [customTableOperationNames] — and [BaseRowRules.customOperationNames]
  /// for why this can't just read `.customOperations.keys` directly here.
  Set<String> customRowOperationNames(String table) =>
      rulesByTable[table]?.row?.customOperationNames ?? const {};

  /// Logs and denies a custom operation name that isn't a key in the
  /// relevant `customOperations` map. Widening `RowOperation.fromString`
  /// from a throw to a nullable `classicOperation` (issue #25) turned an
  /// unrecognized operation name from a loud crash into a 403 — this keeps
  /// that 403 debuggable instead of silent.
  bool _denyUnregisteredCustomOperation({
    required String table,
    required String operation,
    required String scope,
  }) {
    logger.warn(
      'Denied unregistered custom $scope operation "$operation" on "$table" '
      '— not a key in customOperations',
    );
    return false;
  }

  /// `table|operation` pairs already warned about by [_warnUndeclaredWrites].
  final _warnedUndeclaredWrites = <String>{};

  /// Warns when a custom operation's row rule is about to decide on an `after`
  /// that cannot differ from `before`.
  ///
  /// With no updates from either side there is nothing to replay, so `after` is
  /// a copy of `before` and a rule comparing them can only see a row that was
  /// never going to be written. That is either fine — a custom operation that
  /// writes nothing, so `before` really is the outcome — or it is the trap this
  /// warning exists for: an operation whose writes are the server's own, and a
  /// rule silently refusing every call.
  ///
  /// The two are indistinguishable from here, which is why this warns rather
  /// than denies. Once per pair: it is a wiring mistake, not a per-request
  /// event, and a rule evaluated on every redemption would otherwise flood a
  /// log that someone has to keep reading.
  void _warnUndeclaredWrites({
    required String table,
    required String operation,
    required List<Update> updates,
  }) {
    if (updates.isNotEmpty) return;
    if (!_warnedUndeclaredWrites.add('$table|$operation')) return;

    logger.warn(
      'Row rule for custom operation "$operation" on "$table" is deciding on '
      'an unchanged row: no updates were supplied by the caller and none are '
      'declared by the operation, so `after` equals `before`. If the operation '
      'writes anything, override `customUpdates` on its TableOperations to '
      'declare what — otherwise a rule that compares before and after will '
      'refuse every call.',
    );
  }

  Future<TableRulesResponse> _tableRules(TableRulesRequest request) async {
    final rules = rulesByTable[request.table];
    final tableRules = rules?.tableRules;

    if (tableRules == null) {
      logger.warn('No rules found for table: ${request.table}');
      return TableRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canAccess: false,
      );
    }

    final op = request.classicOperation;
    if (op == null) {
      final canAccess =
          switch (tableRules.customOperations[request.operation]) {
            null => _denyUnregisteredCustomOperation(
              table: request.table,
              operation: request.operation,
              scope: 'table',
            ),
            final rule => await rule(request.jwt),
          };

      final rowRules = rulesByTable[request.table]?.row;
      final skipRowChecks = rowRules != null && !rowRules.requiresPerRowCheck;

      return TableRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canAccess: canAccess,
        skipRowChecks: skipRowChecks,
      );
    }

    if (op == .create &&
        tableRules is AuthTableRules &&
        request.jwt?.admin.isAdmin != true) {
      throw StateError('Cannot create auth records, use the auth API instead');
    }

    // ProvisioningJwt is admin-level for the auth table it was issued
    // against, but rejected for any other collection. Scope the
    // elevated-write power to exactly one table; a buggy
    // `onExternalAuthFirstSeen` hook cannot mutate unrelated data.
    final jwt = request.jwt;
    if (jwt is ProvisioningJwt && jwt.authTable != request.table) {
      throw StateError(
        'ProvisioningJwt scoped to "${jwt.authTable}" cannot ${op.name} on "${request.table}"',
      );
    }

    final canAccess = await switch (op) {
      .create => tableRules.canCreate(request.jwt),
      .update => tableRules.canUpdate(request.jwt),
      .delete => tableRules.canDelete(request.jwt),
      .view => tableRules.canView(request.jwt),
      .list => tableRules.canList(request.jwt),
      .count => tableRules.canList(request.jwt),
    };

    final rowRules = rulesByTable[request.table]?.row;
    final skipRowChecks = rowRules != null && !rowRules.requiresPerRowCheck;

    return TableRulesResponse(
      id: request.id,
      table: request.table,
      operation: request.operation,
      canAccess: canAccess,
      skipRowChecks: skipRowChecks,
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
        canList: await tableRules.canList(request.jwt),
        canView: await tableRules.canView(request.jwt),
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

    if (rowRules == null) {
      logger.warn('No rules found for row: ${request.table}');
      return RowRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canPerform: false,
      );
    }

    final op = request.classicOperation;

    if (rowRules case AuthRowRules()
        when op == .create && request.jwt?.admin.isAdmin != true) {
      throw StateError('Cannot create auth rows, use the auth API instead');
    }

    final object = rowRules.table.safeCreate(request.data);

    if (op == null) {
      _warnUndeclaredWrites(
        table: request.table,
        operation: request.operation,
        updates: request.updates,
      );
    }

    final canPerform = await switch (op) {
      .view => rowRules.canView(request.jwt, object),
      .update => rowRules.canUpdate(
        request.jwt,
        object,
        rowRules.table.safeCreate(
          rowRules.table.simulateUpdate(request.data, request.updates),
        ),
      ),
      .delete => rowRules.canDelete(request.jwt, object),
      .create => rowRules.canCreate(request.jwt, object),
      null =>
        rowRules.customOperationCheck(
              request.operation,
              request.jwt,
              object,
              rowRules.table.safeCreate(
                rowRules.table.simulateUpdate(request.data, request.updates),
              ),
            ) ??
            Future.value(
              _denyUnregisteredCustomOperation(
                table: request.table,
                operation: request.operation,
                scope: 'row',
              ),
            ),
    };

    return RowRulesResponse(
      id: request.id,
      table: request.table,
      operation: request.operation,
      canPerform: canPerform,
    );
  }

  Future<BatchRowRulesResponse> _batchRowRules(
    BatchRowRulesRequest request,
  ) async {
    final rules = rulesByTable[request.table];
    final rowRules = rules?.row;
    final op = request.classicOperation;

    if (rowRules == null) {
      logger.warn('No rules found for row: ${request.table}');
      return BatchRowRulesResponse(
        id: request.id,
        table: request.table,
        operation: request.operation,
        canPerform: List<bool>.filled(request.rows.length, false),
      );
    }

    if (rowRules case AuthRowRules()
        when op == .create && request.jwt?.admin.isAdmin != true) {
      throw StateError('Cannot create auth rows, use the auth API instead');
    }

    if (op == null) {
      _warnUndeclaredWrites(
        table: request.table,
        operation: request.operation,
        updates: request.updates,
      );
    }

    final canPerform = <bool>[];
    for (final data in request.rows) {
      final object = rowRules.table.safeCreate(data);
      canPerform.add(await switch (op) {
        .view => rowRules.canView(request.jwt, object),
        .update => rowRules.canUpdate(
          request.jwt,
          object,
          rowRules.table.safeCreate(
            rowRules.table.simulateUpdate(data, request.updates),
          ),
        ),
        .delete => rowRules.canDelete(request.jwt, object),
        .create => rowRules.canCreate(request.jwt, object),
        null =>
          rowRules.customOperationCheck(
                request.operation,
                request.jwt,
                object,
                rowRules.table.safeCreate(
                  rowRules.table.simulateUpdate(data, request.updates),
                ),
              ) ??
              Future.value(
                _denyUnregisteredCustomOperation(
                  table: request.table,
                  operation: request.operation,
                  scope: 'row',
                ),
              ),
      });
    }

    return BatchRowRulesResponse(
      id: request.id,
      table: request.table,
      operation: request.operation,
      canPerform: canPerform,
    );
  }
}
