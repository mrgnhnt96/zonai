import 'dart:async';

import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart' as raindrop show migrate;
import 'package:raindrop/raindrop.dart' show DatabaseResult, Raindrop;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/operation_result.dart';
import 'package:zonai/src/deps/extensions.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/migrate.dart';
import 'package:zonai/src/deps/operations.dart';
import 'package:zonai/src/deps/rules.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';

class ZonaiDb {
  factory ZonaiDb() => _instance ??= ZonaiDb._();
  static ZonaiDb? _instance;
  ZonaiDb._()
    : _extensions = Mailman(
        debugName: 'EXTENSIONS',
        executablePath: extensions.executablePath,
        fromJson: ExtensionResponse.fromJson,
      ),
      _rules = Mailman(
        debugName: 'RULES',
        executablePath: rules.executablePath,
        fromJson: RuleResponse.fromJson,
      ),
      _operations = Mailman(
        debugName: 'OPERATIONS',
        executablePath: operations.executablePath,
        fromJson: OperationResponse.fromJson,
      );

  Raindrop? db;
  final Mailman<ExtensionRequest, ExtensionResponse> _extensions;
  final Mailman<RuleRequest, RuleResponse> _rules;
  final Mailman<OperationRequest, OperationResponse> _operations;

  static const _prefix = '[ZONAI_DB]';

  File? __dbFile;
  File get _dbFile =>
      __dbFile ??= fs.file(fs.path.join(settings.dataPath, 'zonai.sqlite'));

  Future<void> open() async {
    if (this.db != null) {
      return;
    }

    final dir = fs.directory(settings.dataPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    if (!_dbFile.existsSync()) {
      logger.debug('Creating database file: ${_dbFile.path}', prefix: _prefix);
      _dbFile.createSync(recursive: true);
    }

    logger.debug('Opening database: ${_dbFile.path}', prefix: _prefix);
    final db = this.db = Raindrop(SQLiteDelegate.open(_dbFile.path));

    logger.debug('Retrieving migrations', prefix: _prefix);
    final migrations = await migrate.migrations();
    logger.debug('Found ${migrations.length} migrations', prefix: _prefix);

    logger.debug('Migrating database', prefix: _prefix);
    await raindrop.migrate(db, migrations);

    logger.debug('Ensuring database is open', prefix: _prefix);
    await db.ensureOpen();
  }

  Future<PerformOperationResponse> _preChecks(
    String collection, {
    required CollectionOperation operation,
    required Map<String, dynamic> data,
  }) async {
    // todo: get extensions

    logger.debug(
      'Checking collection rules for $collection $operation',
      prefix: _prefix,
    );
    final collectionRules = await _collectionRules(collection, operation);
    logger.debug('Collection rules: $collectionRules', prefix: _prefix);

    if (!collectionRules.canAccess) {
      throw StateError('User does not have access to update $collection');
    }

    logger.debug(
      'Checking record rules for $collection $operation',
      prefix: _prefix,
    );
    final ruleFilter = await _recordRules(
      collection,
      operation.recordOperation,
      data,
    );
    logger.debug('Record rules: $ruleFilter', prefix: _prefix);

    logger.debug(
      'Getting operation for $collection $operation',
      prefix: _prefix,
    );
    return await _getOperation(
      collection,
      operation,
      data: data,
      recordFilter: ruleFilter?.filter,
    );
  }

  Future<(Object? error, Map<String, Object?>? result)> create(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final op = await _preChecks(collection, operation: .create, data: data);
    if (op.query.isEmpty) {
      throw StateError('No query returned for ${CollectionOperation.create}');
    }

    final (error, result) = await execute((
      op.query,
      op.values,
    ), forOperation: .create);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();

    return (null, objects.single);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> update(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final op = await _preChecks(collection, operation: .update, data: data);
    if (op.query.isEmpty) {
      throw StateError('No query returned for ${CollectionOperation.update}');
    }

    final (error, result) = await execute((
      op.query,
      op.values,
    ), forOperation: .update);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.debug('Updated ${objects.length} objects', prefix: _prefix);

    return (null, objects);
  }

  Future<(Object? error, int? result)> delete(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final op = await _preChecks(collection, operation: .delete, data: data);
    if (op.query.isEmpty) {
      throw StateError('No query returned for ${CollectionOperation.delete}');
    }

    final (error, result) = await execute((
      op.query,
      op.values,
    ), forOperation: .delete);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    return (null, result.rowsAffected);
  }

  Future<(Object? error, Map<String, Object?>? result)> view(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final op = await _preChecks(collection, operation: .view, data: data);
    if (op.query.isEmpty) {
      throw StateError('No query returned for ${CollectionOperation.view}');
    }

    final (error, result) = await execute((
      op.query,
      op.values,
    ), forOperation: .view);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.debug('Found ${objects.length} objects', prefix: _prefix);

    return (null, objects.single);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> list(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final op = await _preChecks(collection, operation: .list, data: data);
    if (op.query.isEmpty) {
      throw StateError('No query returned for ${CollectionOperation.list}');
    }

    final (error, result) = await execute((
      op.query,
      op.values,
    ), forOperation: .list);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.debug('Found ${objects.length} objects', prefix: _prefix);

    return (null, objects);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> search(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final op = await _preChecks(collection, operation: .search, data: data);
    if (op.query.isEmpty) {
      throw StateError('No query returned for ${CollectionOperation.search}');
    }

    final (error, result) = await execute((
      op.query,
      op.values,
    ), forOperation: .search);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.debug('Found ${objects.length} objects', prefix: _prefix);

    return (null, objects);
  }

  Future<CanAccessResponse> _collectionRules(
    String collection,
    CollectionOperation operation,
  ) async {
    final rules = await _rules.send(
      CollectionRulesRequest(
        collection: collection,
        operation: operation.name,
        // TODO: Forward user's object
        isSuperUser: true,
      ),
    );

    if (rules is CanAccessResponse) {
      return rules;
    }

    throw StateError('Expected $CanAccessResponse, got ${rules.runtimeType}');
  }

  Future<RecordFilterResponse?> _recordRules(
    String collection,
    RecordOperation operation,
    Map<String, dynamic> data,
  ) async {
    final rules = await _rules.send(
      RecordRulesRequest(
        collection: collection,
        operation: operation,
        isSuperUser: true,
      ),
    );

    if (rules is RecordFilterResponse?) {
      return rules;
    }

    throw StateError(
      'Expected $RecordFilterResponse, got ${rules.runtimeType}',
    );
  }

  Future<PerformOperationResponse> _getOperation(
    String collection,
    CollectionOperation operation, {
    required Map<String, dynamic> data,
    required String? recordFilter,
  }) async {
    final request = switch (operation) {
      .create => CreateOperationRequest(collection: collection, object: data),
      .update => UpdateOperationRequest(
        collection: collection,
        rawRecordFilter: recordFilter,
        updates: [],
        rawWhere: '',
      ),
      .delete => DeleteOperationRequest(
        collection: collection,
        rawRecordFilter: recordFilter,
        rawWhere: '',
        limit: 1,
      ),
      .view => ViewOperationRequest(
        collection: collection,
        rawRecordFilter: recordFilter,
        rawWhere: '',
      ),
      .list => ListOperationRequest(
        collection: collection,
        rawRecordFilter: recordFilter,
        limit: null,
        offset: null,
      ),
      .search => SearchOperationRequest(
        collection: collection,
        rawRecordFilter: recordFilter,
        limit: null,
        offset: null,
        rawWhere: '',
      ),
    };

    final response = await _operations.send(request);

    if (response is PerformOperationResponse) {
      return response;
    }

    throw StateError(
      'Expected $PerformOperationResponse, got ${response.runtimeType}',
    );
  }

  Future<(Object? error, OperationResult? result)> execute(
    (String, List<Object?>) query, {
    List<(String, List<Object?>)>? sideEffects,
    CollectionOperation? forOperation,
  }) async {
    await open();

    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    try {
      DatabaseResult? result;
      await db.transaction((tx) async {
        final (q, v) = query;
        result = await tx.execute(q, v);

        if (sideEffects case final queries?) {
          for (final (query, values) in queries) {
            await tx.execute(query, values);
          }
        }
      });

      return (null, OperationResult(result));
    } catch (e) {
      return (e, null);
    }
  }
}
