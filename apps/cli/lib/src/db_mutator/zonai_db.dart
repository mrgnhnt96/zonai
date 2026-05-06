import 'dart:async';

import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart' as raindrop show migrate;
import 'package:raindrop/raindrop.dart' show DatabaseResult, Raindrop;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/operation_result.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
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
    final db = this.db = Raindrop(await ResqliteDelegate.open(_dbFile.path));

    logger.debug('Retrieving migrations', prefix: _prefix);
    final migrations = await migrate.migrations();
    logger.debug('Found ${migrations.length} migrations', prefix: _prefix);

    logger.debug('Migrating database', prefix: _prefix);
    await raindrop.migrate(db, migrations);

    logger.debug('Ensuring database is open', prefix: _prefix);
    await db.ensureOpen();
  }

  Future<(Object? error, Map<String, Object?>? result)> create(
    String collection,
    CreatePayload payload,
  ) async {
    await _requireCollectionAccess(collection, .create);
    await _requireRecordAccess(collection, .create, payload.object);

    final operation = await _getOperation(
      CreateOperationRequest(collection: collection, object: payload.object),
    );

    final (error, result) = await execute((
      operation.query,
      operation.values,
    ), forOperation: .create);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();

    return (null, objects.single);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> update(
    String collection,
    UpdatePayload payload,
  ) async {
    await _requireCollectionAccess(collection, .update);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where.raw,
        limit: payload.limit,
        offset: null,
      ),
    );

    final (readError, readResult) = await execute((
      readOperation.query,
      readOperation.values,
    ), forOperation: .view);
    if (readError != null || readResult == null) {
      return (readError ?? 'Failed', null);
    }

    for (final row in readResult.rows) {
      await _requireRecordAccess(collection, .update, row.toMap());
    }

    final updateOperation = await _getOperation(
      UpdateOperationRequest(
        collection: collection,
        where: payload.where.raw,
        updates: payload.updates,
      ),
    );

    final (updateError, updateResult) = await execute((
      updateOperation.query,
      updateOperation.values,
    ), forOperation: .update);
    if (updateError != null || updateResult == null) {
      return (updateError ?? 'Failed', null);
    }

    logger.debug('Updated: ${updateResult}', prefix: _prefix);

    return (null, updateResult.rows.map((e) => e.toMap()).toList());
  }

  Future<(Object? error, int? result)> delete(
    String collection,
    DeletePayload payload,
  ) async {
    await _requireCollectionAccess(collection, .delete);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where.raw,
        limit: payload.limit,
        offset: null,
      ),
    );

    logger.debug('Read operation: ${readOperation.query}', prefix: _prefix);

    final (readError, readResult) = await execute((
      readOperation.query,
      readOperation.values,
    ), forOperation: .view);
    if (readError != null || readResult == null) {
      return (readError ?? 'Failed', null);
    }

    if (readResult.rows.isEmpty) {
      return (null, 0);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();
    for (final object in objects) {
      await _requireRecordAccess(collection, .delete, object);
    }

    final deleteOperation = await _getOperation(
      DeleteOperationRequest(
        collection: collection,
        where: payload.where.raw,
        limit: payload.limit,
      ),
    );

    logger.debug('Delete operation: ${deleteOperation.query}', prefix: _prefix);

    final (deleteError, deleteResult) = await execute((
      deleteOperation.query,
      deleteOperation.values,
    ), forOperation: .delete);
    if (deleteError != null || deleteResult == null) {
      return (deleteError ?? 'Failed', null);
    }

    logger.debug('Deleted ${deleteResult}', prefix: _prefix);

    return (null, deleteResult.rowsAffected);
  }

  Future<(Object? error, Map<String, Object?>? result)> view(
    String collection,
    ViewPayload payload,
  ) async {
    await _requireCollectionAccess(collection, .view);

    final operation = await _getOperation(
      ViewOperationRequest(collection: collection, where: payload.where.raw),
    );

    final (error, result) = await execute((
      operation.query,
      operation.values,
    ), forOperation: .view);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    if (result.rows.isEmpty) {
      return (null, null);
    }

    final object = result.rows.first.toMap();
    logger.debug('Found object: ${object}', prefix: _prefix);

    await _requireRecordAccess(collection, .view, object);

    return (null, object);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> list(
    String collection,
    ListPayload payload,
  ) async {
    await _requireCollectionAccess(collection, .view);

    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where.raw,
        limit: payload.limit,
        offset: payload.offset,
      ),
    );

    final (error, result) = await execute((
      operation.query,
      operation.values,
    ), forOperation: .view);
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.debug('Found ${objects.length} objects', prefix: _prefix);

    for (final object in objects) {
      await _requireRecordAccess(collection, .view, object);
    }

    return (null, objects);
  }

  Future<void> _requireCollectionAccess(
    String collection,
    CollectionOperation operation,
  ) async {
    logger.debug(
      'Checking collection rules for $collection $operation',
      prefix: _prefix,
    );
    final collectionRules = await _collectionRules(collection, operation);
    logger.debug('Collection rules: $collectionRules', prefix: _prefix);

    if (!collectionRules.canAccess) {
      throw StateError('User does not have access to update $collection');
    }
  }

  Future<CanAccessResponse> _collectionRules(
    String collection,
    CollectionOperation operation,
  ) async {
    // TODO: Forward user's object
    const isSuperUser = true;

    final rules = await _rules.send(
      CollectionRulesRequest(
        collection: collection,
        operation: operation.name,
        isSuperUser: isSuperUser,
      ),
    );

    if (rules is CanAccessResponse?) {
      return rules ??
          CanAccessResponse(
            id: '-1',
            collection: collection,
            operation: operation.name,
            canAccess: isSuperUser,
          );
    }

    throw StateError('Expected $CanAccessResponse, got ${rules.runtimeType}');
  }

  Future<RecordFilterResponse> _recordRules(
    String collection,
    RecordOperation operation,
    Map<String, dynamic> data,
  ) async {
    final rules = await _rules.send(
      RecordRulesRequest(
        collection: collection,
        operation: operation,
        isSuperUser: true,
        data: data,
      ),
    );

    if (rules is RecordFilterResponse?) {
      return rules ??
          RecordFilterResponse(
            id: '-1',
            collection: collection,
            operation: operation,
            canPerform: true,
          );
    }

    throw StateError(
      'Expected $RecordFilterResponse, got ${rules.runtimeType}',
    );
  }

  Future<void> _requireRecordAccess(
    String collection,
    RecordOperation operation,
    Map<String, dynamic> data,
  ) async {
    final result = await _recordRules(collection, operation, data);
    if (result.canPerform case false) {
      throw StateError(
        'User does not have access to perform $operation on $collection',
      );
    }
  }

  Future<PerformOperationResponse> _getOperation(
    OperationRequest request,
  ) async {
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
