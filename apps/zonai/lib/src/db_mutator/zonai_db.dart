import 'dart:async';

import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart' as raindrop show migrate;
import 'package:raindrop/raindrop.dart' show DatabaseResult, Raindrop;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai/src/internal_collections/jwt_collection.dart';
import 'package:zonai/src/utils/hash_password.dart';
import 'mailman.dart';
import 'operation_result.dart';
import 'payloads/payloads.dart';
import 'sqlite_internal_table_sync.dart';
import '../deps/extensions.dart';
import '../deps/fs.dart';
import '../deps/logger.dart';
import '../deps/migrate.dart';
import '../deps/operations.dart';
import '../deps/rules.dart';
import '../deps/settings.dart';
import '../utils/where_sql.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';

class ZonaiDb {
  ZonaiDb()
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
      logger.verbose(
        'Creating database file: ${_dbFile.path}',
        prefix: _prefix,
      );
      _dbFile.createSync(recursive: true);
    }

    logger.debug('Opening database: ${_dbFile.path}', prefix: _prefix);
    final db = this.db = Raindrop(await ResqliteDelegate.open(_dbFile.path));

    logger.verbose('Retrieving migrations', prefix: _prefix);

    if (await migrate.migrations() case final migrations
        when migrations.isNotEmpty) {
      logger.verbose('Found ${migrations.length} migrations', prefix: _prefix);

      logger.debug('Migrating database', prefix: _prefix);
      await raindrop.migrate(db, migrations);
    }

    await _createInternalCollections(db);

    logger.verbose('Ensuring database is open', prefix: _prefix);
    await db.ensureOpen();
  }

  Future<void> _createInternalCollections(Raindrop db) async {
    final sqlSync = SqliteInternalTableSync(
      onRebuildScheduled: (message) => logger.verbose(message, prefix: _prefix),
    );

    await sqlSync.ensureMatchingTable(db, jwts);
  }

  // TODO(mrgnhnt): Make this configurable
  static const appPepper = 'app_pepper';

  /// Signs in a user if the credentials are valid
  ///
  /// Signs up a user if the record does not exist
  Future<(Object? error, Map<String, Object?>? result)> authenticate(
    String collection,
    AuthPayload payload,
  ) async {
    await _requireAuthCollectionAccess(collection, payload);
    final hasAuthRecord = await _hasAuthRecord(
      collection: collection,
      payload: payload,
    );

    if (!hasAuthRecord) {
      return await signUp(collection, payload);
    }

    return await signIn(collection, payload);
  }

  Future<bool> _hasAuthRecord({
    required String collection,
    required AuthPayload payload,
  }) async {
    final response = await _operations.send(
      ViewAuthOperationRequest(
        collection: collection,
        payload: switch (payload) {
          PasswordAuthPayload() => PasswordAuthOperationPayload.get(
            email: payload.email,
          ),
        },
      ),
    );

    if (response is! PerformOperationResponse) {
      throw StateError('Failed to authenticate');
    }

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw StateError('Failed to authenticate: $error');
    }

    final user = result?.rows.singleOrNull?.toMap();
    return user != null;
  }

  Future<Map<String, Object?>?> _authRecord({
    required String collection,
    required AuthPayload payload,
    required String rawPassword,
  }) async {
    final response = await _operations.send(
      ViewAuthOperationRequest(
        collection: collection,
        payload: switch (payload) {
          PasswordAuthPayload() => PasswordAuthOperationPayload.get(
            email: payload.email,
          ),
        },
      ),
    );

    if (response is! PerformOperationResponse) {
      throw StateError('Failed to authenticate');
    }

    logger.verbose('Auth operation: ${response.query}', prefix: _prefix);

    final (error, result) = await _execute((response.query, response.values));

    if (error != null) {
      throw StateError('Failed to authenticate: $error');
    }

    final user = result?.rows.singleOrNull?.toMap();
    if (user == null) {
      return null;
    }

    final passwordColumn = await _operations.send(
      GetPasswordColumnNameRequest(collection: collection),
    );
    if (passwordColumn is! PasswordColumnNameResponse) {
      logger.trace('Failed to get password column name', prefix: _prefix);
      return null;
    }

    // TODO(mrgnhnt): Send object to extension to sanitize
    final passwordHash = user.remove(passwordColumn.columnName)!;
    if (passwordHash is! String) {
      logger.trace('Password hash not found', prefix: _prefix);
      return null;
    }

    final passwordsMatch = await const HashPassword().verify(
      rawPassword: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
      passwordHash: passwordHash,
      appPepper: appPepper,
    );

    if (!passwordsMatch) {
      throw StateError('Invalid password or email');
    }

    return user;
  }

  Future<(Object? error, Map<String, Object?>? result)> signIn(
    String collection,
    AuthPayload payload,
  ) async {
    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, .signIn, payload);

    final user = await _authRecord(
      collection: collection,
      payload: payload,
      rawPassword: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
    );

    if (user == null) {
      throw StateError('User not found, cannot sign in');
    }

    {
      final onSignIn = await _extensions.send(
        AuthExtensionRequest.onSignIn(collection: collection, object: user),
      );
    }

    return (null, user);
  }

  Future<(Object? error, Map<String, Object?>? result)> signUp(
    String collection,
    AuthPayload payload,
  ) async {
    await _requireAuthCollectionAccess(collection, payload);
    await _requireAuthRecordAccess(collection, .signUp, payload);

    final hashedPassword = await const HashPassword().hash(
      password: switch (payload) {
        PasswordAuthPayload() => payload.password,
      },
      appPepper: appPepper,
    );

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        collection: collection,
        payload: PasswordAuthOperationPayload.save(
          email: payload.email,
          passwordHash: hashedPassword,
          object: payload.object,
        ),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));

    if (error != null || result == null) {
      logger.trace('Failed to create user: $error', prefix: _prefix);
      return (error ?? 'Failed', null);
    }

    final created = result.rows.single.toMap();

    // TODO(mrgnhnt): Send object to extension to sanitize
    final passwordColumn = await _operations.send(
      GetPasswordColumnNameRequest(collection: collection),
    );

    if (passwordColumn is! PasswordColumnNameResponse) {
      logger.trace('Failed to get password column name', prefix: _prefix);
      return (null, null);
    }

    created.remove(passwordColumn.columnName);

    logger.verbose('Created: ${created}', prefix: _prefix);

    {
      final onSignUp = await _extensions.send(
        AuthExtensionRequest.onSignUp(collection: collection, object: created),
      );
    }

    return (null, created);
  }

  Future<void> _requireAuthRecordAccess(
    String collection,
    AuthOperation operation,
    AuthPayload payload,
  ) async {
    final response = await _rules.send(
      AuthRecordRulesRequest(
        collection: collection,
        operation: operation,
        authType: payload.authType,
      ),
    );

    if (response case AuthRecordRulesResponse(canAccess: true)) {
      return;
    }

    throw StateError('User does not have access to $operation on $collection');
  }

  Future<(Object? error, Map<String, Object?>? result)> create(
    String collection,
    CreatePayload payload,
  ) async {
    await _requireCollectionAccess(collection, .create);
    await _requireRecordAccess(collection, .create, payload.object);

    {
      final beforeCreate = await _extensions.send(
        CreateExtensionRequest.before(
          collection: collection,
          object: payload.object,
        ),
      );
    }

    final operation = await _getOperation(
      CreateOperationRequest(collection: collection, object: payload.object),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      final afterCreate = await _extensions.send(
        ErrorExtensionRequest.create(
          collection: collection,

          error: error?.toString() ?? 'Unknown error',
        ),
      );

      return (error ?? 'Failed', null);
    }

    final created = result.rows.single.toMap();
    logger.verbose('Created: ${created}', prefix: _prefix);

    {
      final afterCreate = await _extensions.send(
        CreateExtensionRequest.afterSuccess(
          collection: collection,
          object: payload.object,
        ),
      );
    }

    return (null, created);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> update(
    String collection,
    UpdatePayload payload,
  ) async {
    await _requireCollectionAccess(collection, .update);

    final where = payload.where.sql(collection);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
        offset: null,
      ),
    );

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    if (readError != null || readResult == null) {
      return (readError ?? 'Failed', null);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      await _requireRecordAccess(collection, .update, row);
    }

    {
      final beforeUpdate = await _extensions.send(
        BeforeUpdateExtensionRequest(collection: collection, objects: objects),
      );
    }

    final updateOperation = await _getOperation(
      UpdateOperationRequest(
        collection: collection,
        where: where,
        updates: payload.updates,
      ),
    );

    final (updateError, updateResult) = await _execute((
      updateOperation.query,
      updateOperation.values,
    ));
    if (updateError != null || updateResult == null) {
      return (updateError ?? 'Failed', null);
    }

    logger.verbose('Updated: ${updateResult}', prefix: _prefix);

    // `updateResult.rows` always returns empty, need to refetch the records
    final (updatedError, updatedResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    if (updatedError != null || updatedResult == null) {
      final afterUpdate = await _extensions.send(
        ErrorExtensionRequest.update(
          collection: collection,
          error: updatedError?.toString() ?? 'Unknown error',
        ),
      );

      return (updatedError ?? 'Failed', null);
    }

    final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();
    logger.verbose('Updated objects: ${updatedObjects}', prefix: _prefix);

    {
      final afterUpdate = await _extensions.send(
        AfterUpdateExtensionRequest(
          collection: collection,
          before: objects,
          after: updatedObjects,
        ),
      );
    }

    return (null, updatedObjects);
  }

  Future<(Object? error, int? result)> delete(
    String collection,
    DeletePayload payload,
  ) async {
    await _requireCollectionAccess(collection, .delete);

    final where = payload.where.sql(collection);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
        offset: null,
      ),
    );

    logger.verbose('Read operation: ${readOperation.query}', prefix: _prefix);

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
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

    {
      final beforeDelete = await _extensions.send(
        DeleteExtensionRequest.before(collection: collection, objects: objects),
      );
    }

    final deleteOperation = await _getOperation(
      DeleteOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
      ),
    );

    logger.verbose(
      'Delete operation: ${deleteOperation.query}',
      prefix: _prefix,
    );

    final (deleteError, deleteResult) = await _execute((
      deleteOperation.query,
      deleteOperation.values,
    ));
    if (deleteError != null || deleteResult == null) {
      final afterDelete = await _extensions.send(
        ErrorExtensionRequest.delete(
          collection: collection,
          error: deleteError?.toString() ?? 'Unknown error',
        ),
      );

      return (deleteError ?? 'Failed', null);
    }

    logger.verbose('Deleted ${deleteResult}', prefix: _prefix);

    {
      final afterDelete = await _extensions.send(
        DeleteExtensionRequest.afterSuccess(
          collection: collection,
          objects: objects,
        ),
      );
    }

    return (null, deleteResult.rowsAffected);
  }

  Future<(Object? error, Map<String, Object?>? result)> view(
    String collection,
    ViewPayload payload,
  ) async {
    await _requireCollectionAccess(collection, .view);

    final operation = await _getOperation(
      ViewOperationRequest(
        collection: collection,
        where: payload.where.sql(collection),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    if (result.rows.isEmpty) {
      return (null, null);
    }

    final object = result.rows.first.toMap();
    logger.verbose('Found object: ${object}', prefix: _prefix);

    await _requireRecordAccess(collection, .view, object);

    return (null, object);
  }

  Future<(Object? error, List<Map<String, Object?>>? result)> list(
    String collection,
    ListPayload payload,
  ) async {
    await _requireCollectionAccess(collection, .list);

    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where?.sql(collection),
        limit: payload.limit,
        offset: payload.offset,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.verbose('Found ${objects.length} objects', prefix: _prefix);

    for (final object in objects) {
      await _requireRecordAccess(collection, .view, object);
    }

    return (null, objects);
  }

  Stream<List<Map<String, Object?>>> streamList(
    String collection,
    ListPayload payload,
  ) async* {
    await _requireCollectionAccess(collection, .list);

    final where = payload.where?.sql(collection);
    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
        offset: payload.offset,
      ),
    );

    final (readError, readResult) = await _execute((
      operation.query,
      operation.values,
    ));
    if (readError != null || readResult == null) {
      throw StateError('Failed to read records: $readError');
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();
    for (final object in objects) {
      await _requireRecordAccess(collection, .view, object);
    }

    await for (final result in _stream(operation.query, operation.values)) {
      yield result.rows.map((e) => e.toMap()).toList();
    }
  }

  Stream<Map<String, Object?>> streamOne(
    String collection,
    ViewPayload payload,
  ) async* {
    await _requireCollectionAccess(collection, .view);

    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where.sql(collection),
        limit: 1,
        offset: null,
      ),
    );

    final (readError, readResult) = await _execute((
      operation.query,
      operation.values,
    ));
    if (readError != null || readResult == null) {
      throw StateError('Failed to read record: $readError');
    }

    final object = readResult.rows.single.toMap();
    await _requireRecordAccess(collection, .view, object);

    await for (final result in _stream(operation.query, operation.values)) {
      yield result.rows.single.toMap();
    }
  }

  Future<void> _requireAuthCollectionAccess(
    String collection,
    AuthPayload payload,
  ) async {
    final response = await _rules.send(
      AuthCollectionRulesRequest(
        collection: collection,
        authType: switch (payload) {
          PasswordAuthPayload() => .password,
        },
      ),
    );

    if (response case AuthCollectionRulesResponse(canAuthenticate: true)) {
      return;
    }

    throw StateError('Cannot authenticate for collection: $collection');
  }

  Future<void> _requireCollectionAccess(
    String collection,
    CollectionOperation operation,
  ) async {
    logger.verbose(
      'Checking collection rules for $collection $operation',
      prefix: _prefix,
    );
    final collectionRules = await _collectionRules(collection, operation);
    logger.verbose('Collection rules: $collectionRules', prefix: _prefix);

    if (!collectionRules.canAccess) {
      throw StateError('User does not have access to update $collection');
    }
  }

  Future<CollectionRulesResponse> _collectionRules(
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

    if (rules is CollectionRulesResponse?) {
      return rules ??
          CollectionRulesResponse(
            id: '-1',
            collection: collection,
            operation: operation.name,
            canAccess: isSuperUser,
          );
    }

    throw StateError(
      'Expected $CollectionRulesResponse, got ${rules.runtimeType}',
    );
  }

  Future<RecordRulesResponse> _recordRules(
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

    if (rules is RecordRulesResponse?) {
      return rules ??
          RecordRulesResponse(
            id: '-1',
            collection: collection,
            operation: operation,
            canPerform: true,
          );
    }

    throw StateError('Expected $RecordRulesResponse, got ${rules.runtimeType}');
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

  Future<(Object? error, OperationResult? result)> _execute(
    (String, List<Object?>) query, {
    List<(String, List<Object?>)>? sideEffects,
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

  Stream<OperationResult> _stream(String query, List<Object?> values) async* {
    await open();

    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    try {
      logger.verbose('Streaming query: $query', prefix: _prefix);
      final stream = db.streamQuery(query, values);
      await for (final result in stream) {
        yield OperationResult(result);
      }

      logger.verbose('Stream completed: $query', prefix: _prefix);
    } catch (e) {
      logger.error('Error streaming query: $query');
    }
  }
}
