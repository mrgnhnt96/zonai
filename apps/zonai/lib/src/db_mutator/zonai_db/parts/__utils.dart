part of zonai_db;

extension _UtilsX on ZonaiDb {
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

  Future<void> _requireCollectionAccess(
    String collection,
    CollectionOperation operation,
    Jwt? jwt,
  ) async {
    logger.verbose(
      'Checking collection rules for $collection $operation',
      prefix: _prefix,
    );
    final collectionRules = await _collectionRules(collection, operation, jwt);
    logger.verbose('Collection rules: $collectionRules', prefix: _prefix);

    if (!collectionRules.canAccess) {
      throw StateError(
        'User permissions are restricted. Action: "${operation.name}" on collection: "$collection"',
      );
    }
  }

  Future<CollectionRulesResponse> _collectionRules(
    String collection,
    CollectionOperation operation,
    Jwt? jwt,
  ) async {
    final rules = await _rules.send(
      CollectionRulesRequest(
        collection: collection,
        operation: operation.name,
        jwt: jwt,
      ),
    );

    if (rules is CollectionRulesResponse?) {
      return rules ??
          CollectionRulesResponse(
            id: '-1',
            collection: collection,
            operation: operation.name,
            canAccess: false,
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
    Jwt? jwt,
  ) async {
    final rules = await _rules.send(
      RecordRulesRequest(
        collection: collection,
        operation: operation,
        data: data,
        jwt: jwt,
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
    Jwt? jwt,
  ) async {
    final result = await _recordRules(collection, operation, data, jwt);
    if (result.canPerform case false) {
      throw StateError(
        'User permissions are restricted. Action: "${operation.name}" on collection: "$collection"',
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
