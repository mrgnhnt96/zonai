part of zonai_db;

extension UtilsX on ZonaiDb {
  File get _dbFile => __dbFile ??= fs.file(settings.zonaiSqlitePath);

  Future<Raindrop> open() async {
    if (this.db case final db?) {
      return db;
    }

    await ensureResqliteNativeInstalled();

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

    logger.verbose(
      'Applying (${InternalDbMigrate.migrations.length}) internal table migrations',
      prefix: _prefix,
    );
    await InternalDbMigrate.apply(db);

    await _createInternalCollections(db);

    logger.verbose('Retrieving migrations', prefix: _prefix);

    if (await migrate.migrations() case final migrations
        when migrations.isNotEmpty) {
      logger.verbose('Found ${migrations.length} migrations', prefix: _prefix);

      logger.debug('Migrating database', prefix: _prefix);
      await raindrop.migrate(db, migrations);
    }

    logger.verbose('Ensuring database is open', prefix: _prefix);
    await db.ensureOpen();

    return db;
  }

  Future<void> _createInternalCollections(Raindrop db) async {
    final sqlSync = SqliteInternalTableSync();

    for (final schema in InternalDbArtifacts.schemas) {
      await sqlSync.ensureMatchingTable(db, schema);
    }
  }

  Future<void> _requireTableAccess(
    String table,
    TableOperation operation,
    Jwt? jwt,
  ) async {
    logger.verbose(
      'Checking table rules for $table $operation',
      prefix: _prefix,
    );
    final tableRules = await _tableRules(table, operation, jwt);

    if (!tableRules.canAccess) {
      throw StateError(
        'User permissions are restricted. Action: "${operation.name}" on table: "$table"',
      );
    }
  }

  Future<TableRulesResponse> _tableRules(
    String table,
    TableOperation operation,
    Jwt? jwt,
  ) async {
    final rules = await _rules.send<TableRulesResponse?>(
      TableRulesRequest(table: table, operation: operation.name, jwt: jwt),
    );

    return rules ??
        TableRulesResponse(
          id: '-1',
          table: table,
          operation: operation.name,
          canAccess: false,
        );
  }

  Future<RowRulesResponse> _rowRules(
    String table,
    RowOperation operation,
    Map<String, dynamic> data,
    Jwt? jwt,
  ) async {
    final rules = await _rules.send<RowRulesResponse?>(
      RowRulesRequest(table: table, operation: operation, data: data, jwt: jwt),
    );

    return rules ??
        RowRulesResponse(
          id: '-1',
          table: table,
          operation: operation,
          canPerform: true,
        );
  }

  Future<void> _requireRowAccess(
    String table,
    RowOperation operation,
    Map<String, dynamic> data,
    Jwt? jwt,
  ) async {
    final result = await _rowRules(table, operation, data, jwt);
    if (result.canPerform case false) {
      throw StateError(
        'User permissions are restricted. Action: "$operation" on table: "$table"',
      );
    }
  }

  Future<PerformOperationResponse> _getOperation(
    OperationRequest request,
  ) async {
    return await _operations.send<PerformOperationResponse>(request);
  }

  Future<Map<String, Object?>> _sanitizeRow(
    String table,
    Map<String, Object?> row,
  ) async {
    final rows = await _sanitizeRows(table, [row]);
    return rows.single;
  }

  Future<List<Map<String, Object?>>> _sanitizeRows(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return const [];
    }

    final response = await _operations.send<SanitizeOperationResponse>(
      SanitizeOperationRequest(table: table, objects: rows),
    );

    return _resolvePhotoFields(response.objects, response.photoColumns);
  }

  Future<List<_SideEffect>> _getEffect(MutationRequest mut) async {
    switch (mut) {
      case final DeleteRecordRequest mut:
        final (objects, :deleteOperation) = await _deleteOperation(
          mut.table,
          DeletePayload(where: mut.where, limit: mut.limit),
          mut.jwt,
        );

        logger.trace('(SIDE EFFECT) Deleting records: ${objects.length}');

        return [
          _DeleteSideEffect(
            request: mut,
            objects: objects,
            operation: deleteOperation,
          ),
        ];

      // perform operation
      case final UpdateRecordRequest mut:
        final (
          objects,
          :readOperation,
          :updateOperation,
        ) = await _updateOperation(
          mut.table,
          UpdatePayload(where: mut.where, updates: mut.updates),
          mut.jwt,
        );

        if (objects.isEmpty) {
          return [];
        }

        logger.trace('(SIDE EFFECT) Updating records: ${objects.length}');

        return [
          _UpdateSideEffect(
            request: mut,
            before: objects,
            operation: updateOperation,
            readOperation: readOperation,
          ),
        ];

      case final CreateRecordRequest mut:
        if (mut.objects.isEmpty) {
          return [];
        }

        await _requireTableAccess(mut.table, .create, mut.jwt);
        final futures = <Future<_CreateSideEffect>>[];
        for (final object in mut.objects) {
          final operation = _createOperation(
            mut.table,
            CreatePayload(object: object),
            mut.jwt,
          );

          futures.add(
            operation.then(
              (value) => _CreateSideEffect(request: mut, operation: value),
            ),
          );
        }

        logger.debug('(SIDE EFFECT) Creating records: ${mut.objects.length}');

        return await Future.wait(futures);
    }
  }

  Future<(Object? error, OperationResult? result)> _execute(
    (String, List<Object?>) query,
  ) async {
    await open();

    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    final effects = <_SideEffect>[];
    if (mutations.extract case final muts when muts.isNotEmpty) {
      logger.debug('(SIDE EFFECT) Handling (${muts.length}) mutations');
      final groupedEffects = await Future.wait([
        for (final mut in muts) _getEffect(mut),
      ]);

      effects.addAll(groupedEffects.expand((e) => e).toList());
    }

    DatabaseResult? result;
    try {
      await db.transaction((tx) async {
        final (q, v) = query;
        result = await tx.execute(q, v);

        for (final effect in effects.whereType<PerformOperationResponse>()) {
          await tx.execute(effect.query, effect.values);
        }
      });
    } catch (e) {
      return (e, null);
    }

    return (null, OperationResult(result));
  }

  Future<void> _executeEffects() async {
    final db = this.db;
    if (db == null) {
      throw StateError('Database is not open');
    }

    const maxIterations = 10;
    var iterations = 0;
    List<MutationRequest> remainingEffects = mutations.extract;
    while (remainingEffects.isNotEmpty && iterations < maxIterations) {
      logger.trace(
        'Executing effects: ${remainingEffects.length} (iterations: $iterations)',
        prefix: _prefix,
      );
      final groupedEffects = await Future.wait([
        for (final mut in remainingEffects) _getEffect(mut),
      ]);
      final effects = groupedEffects.expand((e) => e).toList();

      final operationResults = <_SideEffect, OperationResult>{};

      await db.transaction((tx) async {
        for (final effect in effects) {
          final result = await tx.execute(
            effect.operation.query,
            effect.operation.values,
          );
          operationResults[effect] = OperationResult(result);
        }
      });

      for (final effect in effects) {
        switch (effect) {
          case _DeleteSideEffect():
            await _postDelete(
              effect.request.table,
              effect.request.jwt,
              objects: effect.objects,
            );
          case _CreateSideEffect():
            final raw = operationResults[effect]?.rows.single.toMap();
            if (raw != null) {
              final created = await _sanitizeRow(effect.request.table, raw);
              await _postCreate(
                effect.request.table,
                effect.request.jwt,
                object: created,
              );
            } else {
              logger.error('(SIDE EFFECT) Unexpected error during create');
            }
          case _UpdateSideEffect(:final readOperation):
            // `updateResult.rows` always returns empty, need to refetch the records
            final (_, updatedResult) = await _execute((
              readOperation.query,
              readOperation.values,
            ));

            final afterRows = updatedResult?.rows
                .map((e) => e.toMap())
                .toList();

            if (afterRows != null) {
              final after = await _sanitizeRows(
                effect.request.table,
                afterRows,
              );

              await _postUpdate(
                effect.request.table,
                effect.request.jwt,
                before: effect.before,
                after: after,
              );
            } else {
              logger.error('(SIDE EFFECT) Unexpected error during update');
            }
        }
      }

      remainingEffects = mutations.extract;
      iterations++;
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

sealed class _SideEffect {
  const _SideEffect({required this.operation});

  final PerformOperationResponse operation;
}

class _DeleteSideEffect extends _SideEffect {
  const _DeleteSideEffect({
    required this.request,
    required super.operation,
    required this.objects,
  });

  final DeleteRecordRequest request;
  final List<Map<String, Object?>> objects;
}

class _CreateSideEffect extends _SideEffect {
  const _CreateSideEffect({required this.request, required super.operation});

  final CreateRecordRequest request;
}

class _UpdateSideEffect extends _SideEffect {
  const _UpdateSideEffect({
    required this.request,
    required this.readOperation,
    required this.before,
    required super.operation,
  });

  final PerformOperationResponse readOperation;
  final UpdateRecordRequest request;
  final List<Map<String, Object?>> before;
}
