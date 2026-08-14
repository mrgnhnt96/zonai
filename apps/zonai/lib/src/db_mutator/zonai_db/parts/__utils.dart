part of zonai_db;

extension UtilsX on ZonaiDb {
  File get _dbFile => __dbFile ??= fs.file(settings.zonaiSqlitePath);

  /// The `_log` table's own file. Created by SQLite on the first write
  /// through the attach, so it is not pre-created here.
  File get _logDbFile => __logDbFile ??= fs.file(settings.zonaiLogSqlitePath);

  /// The `_rate_limit` table's own file. Created lazily, as above.
  File get _rateLimitDbFile =>
      __rateLimitDbFile ??= fs.file(settings.zonaiRateLimitSqlitePath);

  Future<T?> _dispatchRules<T extends RuleResponse>(RuleRequest request) async {
    if (HostWorkerRegistries.useInProcessRules) {
      final response = await HostWorkerRegistries.rules!.dispatch(request);
      if (response is T) return response;
      throw StateError(
        'In-process rules returned ${response.runtimeType}, expected $T',
      );
    }
    return _rules.send<T>(request);
  }

  Future<T> _dispatchOperation<T extends OperationResponse>(
    OperationRequest request,
  ) async {
    if (HostWorkerRegistries.useInProcessOperations) {
      final response = await HostWorkerRegistries.operations!.dispatch(request);
      if (response is T) return response;
      throw StateError(
        'In-process operations returned ${response.runtimeType}, expected $T',
      );
    }
    return _operations.send<T>(request);
  }

  Future<Raindrop> open() async {
    if (this.db case final db?) {
      return db;
    }

    return _opening ??= _openOnce().whenComplete(() => _opening = null);
  }

  Future<Raindrop> _openOnce() async {
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
    await ensureResqliteNativeInstalled();
    final delegate = await ResqliteDelegate.open(
      _dbFile.path,
      attach: {
        kLogDbSchema: _logDbFile.path,
        kRateLimitDbSchema: _rateLimitDbFile.path,
      },
      // Opt-in and absent by default -- see `Settings.logDatabaseMaxBytes`
      // for why a ceiling is not imposed on a deployment that never asked
      // for one. `_rate_limit` gets none at all: it is bounded by its own
      // retention window rather than by growth, and capping it would start
      // failing the writes that enforce the limits.
      maxBytes: {
        if (settings.logDatabaseMaxBytes case final bytes?) kLogDbSchema: bytes,
      },
    );
    final db = Raindrop(delegate);

    try {
      logger.verbose(
        'Applying (${InternalDbMigrate.migrations.length}) internal table migrations',
        prefix: _prefix,
      );
      await InternalDbMigrate.apply(db);
      await _ensureDisposableTables(db);
      await _createInternalCollections(db);

      logger.verbose('Retrieving migrations', prefix: _prefix);
      if (await migrate.migrations() case final migrations
          when migrations.isNotEmpty) {
        logger.verbose(
          'Found ${migrations.length} migrations',
          prefix: _prefix,
        );

        logger.debug('Migrating database', prefix: _prefix);
        await raindrop.migrate(db, migrations);
      }
    } catch (_) {
      await delegate.close();
      rethrow;
    }

    return this.db = db;
  }

  ResqliteDelegate get _resqlite {
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }
    if (db.delegate case final ResqliteDelegate delegate) {
      return delegate;
    }
    throw StateError(
      'Expected ResqliteDelegate, got ${db.delegate.runtimeType}',
    );
  }

  Future<void> _createInternalCollections(Raindrop db) async {
    final sqlSync = SqliteInternalTableSync();

    for (final schema in InternalDbArtifacts.schemas) {
      // Disposable tables live in their own files and were created by
      // [_ensureDisposableTables], which has already run. Letting one through
      // here would create a *second* copy in `main` -- and `main` wins name
      // resolution, so every write would silently go back to the shared file
      // the split exists to keep it out of.
      if (_disposableTableSchemas.containsKey(schema.$.name)) continue;
      await sqlSync.ensureMatchingTable(db, schema);
    }
  }

  /// Moves the disposable tables into their own database files, dropping
  /// whatever was in `main`.
  ///
  /// Deliberately not a data migration. These tables are disposable in the
  /// literal sense -- log lines past their retention window, rate-limit
  /// counters whose whole lifetime is one window -- and the deployments that
  /// need this most are the ones holding millions of rows on a volume with no
  /// room to copy anything. Dropping is also what returns their pages to
  /// `main`'s freelist, which is the first half of reclaiming that space; the
  /// second is a `VACUUM`, which `zonai db logs clear --vacuum` still runs
  /// against `main` for exactly this reason.
  ///
  /// Order matters and is the whole trick: the drop has to happen before the
  /// create, because an unqualified name resolves into an attached database
  /// only while `main` has no table by that name.
  ///
  /// Idempotent -- on every open after the first, every statement is a no-op.
  Future<void> _ensureDisposableTables(Raindrop db) async {
    final sqlSync = SqliteInternalTableSync();

    for (final schema in InternalDbArtifacts.schemas) {
      final table = schema.$.name;
      final sqliteSchema = _disposableTableSchemas[table];
      if (sqliteSchema == null) continue;

      if (await _mainHasTable(db, table)) {
        // `warn`, not `info`: this happens once per database and it discards
        // rows. An operator who did not expect that should see it.
        logger.warn(
          'Moving "$table" into its own database file. Existing rows are '
          'dropped; run `zonai db logs clear --vacuum` to return their disk '
          'space to the operating system.',
          prefix: _prefix,
        );
        // Drops the table's indexes with it.
        await db.execute('DROP TABLE IF EXISTS "main"."$table"');
      }

      await sqlSync.ensureMatchingTable(db, schema, sqliteSchema: sqliteSchema);

      // Recreated here rather than left to the generated migrations: those
      // ran against `main` and were dropped along with the table above.
      // Without them the dashboard's level/timestamp queries, every retention
      // cutoff, and the rate limiter's per-request bucket lookup all degrade
      // to full scans -- of the two tables written most often.
      for (final ddl in _disposableTableIndexes[table] ?? const <String>[]) {
        await db.execute(ddl.replaceAll(r'$schema', sqliteSchema));
      }
    }
  }

  Future<bool> _mainHasTable(Raindrop db, String table) async {
    final result = await db.execute(
      'SELECT 1 FROM "main".sqlite_master '
      "WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return result.rows.isNotEmpty;
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
      throw TableAccessDeniedException(table: table, operation: operation.name);
    }

    if (tableRules.skipRowChecks) {
      _skipRowChecks['$table|${_jwtCacheKey(jwt)}'] = true;
    }
  }

  Future<TableRulesResponse> _tableRules(
    String table,
    TableOperation operation,
    Jwt? jwt,
  ) async {
    final cacheKey = '$table|${operation.name}|${_jwtCacheKey(jwt)}';
    final cached = _tableAccessCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final rules = await _dispatchRules<TableRulesResponse>(
      TableRulesRequest(table: table, operation: operation.name, jwt: jwt),
    );

    final response =
        rules ??
        TableRulesResponse(
          id: '-1',
          table: table,
          operation: operation.name,
          canAccess: false,
        );
    _tableAccessCache[cacheKey] = response;
    return response;
  }

  /// Custom-operation counterpart of [_requireTableAccess] — [operation] is
  /// an arbitrary name (`TableOperations.custom`), not a [TableOperation],
  /// so it can't go through the enum-typed helper above.
  Future<void> _requireCustomTableAccess(
    String table,
    String operation,
    Jwt? jwt,
  ) async {
    logger.verbose(
      'Checking table rules for $table custom:$operation',
      prefix: _prefix,
    );
    final tableRules = await _customTableRules(table, operation, jwt);

    if (!tableRules.canAccess) {
      throw TableAccessDeniedException(table: table, operation: operation);
    }

    if (tableRules.skipRowChecks) {
      _skipRowChecks['$table|${_jwtCacheKey(jwt)}'] = true;
    }
  }

  Future<TableRulesResponse> _customTableRules(
    String table,
    String operation,
    Jwt? jwt,
  ) async {
    final cacheKey = '$table|$operation|${_jwtCacheKey(jwt)}';
    final cached = _tableAccessCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final rules = await _dispatchRules<TableRulesResponse>(
      TableRulesRequest(table: table, operation: operation, jwt: jwt),
    );

    final response =
        rules ??
        TableRulesResponse(
          id: '-1',
          table: table,
          operation: operation,
          canAccess: false,
        );
    _tableAccessCache[cacheKey] = response;
    return response;
  }

  Future<RowRulesResponse> _rowRules(
    String table,
    RowOperation operation,
    Map<String, dynamic> data,
    Jwt? jwt, {
    List<Update> updates = const [],
  }) async {
    if (_skipRowChecks['$table|${_jwtCacheKey(jwt)}'] == true) {
      return RowRulesResponse(
        id: '-1',
        table: table,
        operation: operation.name,
        canPerform: true,
      );
    }

    final rules = await _dispatchRules<RowRulesResponse>(
      RowRulesRequest(
        table: table,
        operation: operation.name,
        data: data,
        updates: updates,
        jwt: jwt,
      ),
    );

    return rules ??
        RowRulesResponse(
          id: '-1',
          table: table,
          operation: operation.name,
          canPerform: false,
        );
  }

  Future<void> _requireRowAccess(
    String table,
    RowOperation operation,
    Map<String, dynamic> data,
    Jwt? jwt, {
    List<Update> updates = const [],
  }) async {
    final result = await _rowRules(
      table,
      operation,
      data,
      jwt,
      updates: updates,
    );
    if (result.canPerform case false) {
      throw RowAccessDeniedException(
        table: table,
        operation: operation.toString(),
      );
    }
  }

  /// Batch equivalent of [_requireRowAccess] for multi-row reads.
  ///
  /// One rules-worker round-trip for the whole page instead of N sequential
  /// hops. Preserves fail-closed semantics: any denied row fails the call.
  /// Skipped entirely when table rules reported [TableRulesResponse.skipRowChecks].
  Future<void> _requireRowsAccess(
    String table,
    RowOperation operation,
    List<Map<String, dynamic>> rows,
    Jwt? jwt, {
    List<Update> updates = const [],
  }) async {
    if (rows.isEmpty) return;
    if (_skipRowChecks['$table|${_jwtCacheKey(jwt)}'] == true) return;

    final response = await _dispatchRules<BatchRowRulesResponse>(
      BatchRowRulesRequest(
        table: table,
        operation: operation.name,
        rows: rows,
        updates: updates,
        jwt: jwt,
      ),
    );

    final allowed = response?.canPerform;
    if (allowed == null || allowed.length != rows.length) {
      throw RowAccessDeniedException(
        table: table,
        operation: operation.toString(),
      );
    }

    for (final canPerform in allowed) {
      if (!canPerform) {
        throw RowAccessDeniedException(
          table: table,
          operation: operation.toString(),
        );
      }
    }
  }

  /// Custom-operation counterpart of [_requireRowAccess] — [operation] is an
  /// arbitrary name (`TableOperations.custom`), not a [RowOperation].
  Future<void> _requireCustomRowAccess(
    String table,
    String operation,
    Map<String, dynamic> data,
    Jwt? jwt, {
    List<Update> updates = const [],
  }) async {
    if (_skipRowChecks['$table|${_jwtCacheKey(jwt)}'] == true) return;

    final rules = await _dispatchRules<RowRulesResponse>(
      RowRulesRequest(
        table: table,
        operation: operation,
        data: data,
        updates: updates,
        jwt: jwt,
      ),
    );

    if ((rules?.canPerform ?? false) case false) {
      throw RowAccessDeniedException(table: table, operation: operation);
    }
  }

  Future<PerformOperationResponse> _getOperation(
    OperationRequest request,
  ) async {
    final cacheKey = _operationCacheKey(request);
    if (cacheKey != null) {
      final cached = _operationCache[cacheKey];
      if (cached != null) return cached;
    }

    final response = await _dispatchOperation<PerformOperationResponse>(
      request,
    );
    if (cacheKey != null) {
      _operationCache[cacheKey] = response;
    }
    return response;
  }

  /// Cached [GetColumnNameRequest] results (including `null` = column absent).
  Future<String?> _cachedColumnName(String table, ColumnName columnName) async {
    final key = '$table|${columnName.name}';
    if (_columnNameCache.containsKey(key)) {
      return _columnNameCache[key];
    }

    final response = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: columnName),
    );
    return _columnNameCache[key] = response.name;
  }

  /// No-ops when the project has no extension handlers registered.
  Future<void> _runExtension(ExtensionRequest request) async {
    if (HostWorkerRegistries.useInProcessExtensions) {
      await HostWorkerRegistries.extensions!.dispatch(request);
      return;
    }
    if (!_detectProjectExtensions()) {
      return;
    }
    await _extensions.send<NoActionExtensionResponse>(request);
  }

  bool _detectProjectExtensions() {
    if (HostWorkerRegistries.hasExtensions) {
      return _hasProjectExtensions = true;
    }
    if (_hasProjectExtensions case final cached?) {
      return cached;
    }

    if (InternalDbArtifacts.extensions.isNotEmpty) {
      return _hasProjectExtensions = true;
    }

    // The compiled worker is what a deployed/built server actually ships and
    // spawns -- a `zonai build` bundle (or the scratch-dir shape used by
    // integration tests) has no `lib/` source tree at all, so checking only
    // the source directory below would report "no extensions" and silently
    // skip every beforeCreate/beforeUpdate hook.
    if (fs.file(settings.compiledExtensionsPath).existsSync()) {
      return _hasProjectExtensions = true;
    }

    final dir = fs.directory(settings.extensionsPath);
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          return _hasProjectExtensions = true;
        }
      }
    }

    logger.warn(
      'No extensions detected (checked ${settings.compiledExtensionsPath} '
      'and ${settings.extensionsPath}) -- beforeCreate/beforeUpdate hooks '
      'will not run for this process',
      prefix: _prefix,
    );
    return _hasProjectExtensions = false;
  }

  String? _operationCacheKey(OperationRequest request) {
    // Only cache pure SQL-build reads — mutation SQL often embeds row values.
    return switch (request) {
      CountOperationRequest(:final table, :final where, :final jwt) =>
        'count|$table|${jsonEncode(where?.toJson())}|${_jwtCacheKey(jwt)}',
      ListOperationRequest(
        :final table,
        :final where,
        :final limit,
        :final offset,
        :final orderBy,
        :final groupBy,
        :final jwt,
      ) =>
        'list|$table|${jsonEncode(where?.toJson())}|$limit|$offset|'
            '${jsonEncode([for (final term in orderBy ?? const <OrderByTerm>[]) term.toJson()])}|$groupBy|${_jwtCacheKey(jwt)}',
      ReadOperationRequest(:final table, :final where, :final jwt) =>
        'read|$table|${jsonEncode(where.toJson())}|${_jwtCacheKey(jwt)}',
      _ => null,
    };
  }

  String _jwtCacheKey(Jwt? jwt) {
    if (jwt == null) return '';
    return '${jwt.userId.value}|${jwt.admin.isAdmin}|${jwt.admin.canEdit}';
  }

  Never _throwDatabaseError(
    Object? error, {
    required String table,
    required CrudException Function([Object? cause]) failure,
  }) {
    if (error == null) {
      throw failure(null);
    }

    throw mapDatabaseError(
      error,
      table: table,
      orElse: (cause) => failure(cause),
    );
  }

  bool _preserveSecretsForJwt(Jwt? jwt) =>
      jwt?.admin.isAdmin == true || jwt?.admin.canEdit == true;

  Future<Map<String, Object?>> _sanitizeRow(
    String table,
    Map<String, Object?> row, {
    Jwt? jwt,
  }) async {
    final rows = await _sanitizeRows(table, [row], jwt: jwt);
    return rows.single;
  }

  Future<List<Map<String, Object?>>> _sanitizeRows(
    String table,
    List<Map<String, Object?>> rows, {
    Jwt? jwt,
  }) async {
    if (rows.isEmpty) {
      return const [];
    }

    final preserveSecrets = _preserveSecretsForJwt(jwt);
    final meta = await _sanitizeMetaFor(table);
    final cleaned = <Map<String, Object?>>[
      for (final row in rows)
        {
          for (final MapEntry(:key, :value) in row.entries)
            if (preserveSecrets || !meta.secretColumns.contains(key))
              key: value,
        },
    ];
    return _resolvePhotoFields(cleaned, meta.photoColumns);
  }

  Future<({List<String> secretColumns, List<String> photoColumns})>
  _sanitizeMetaFor(String table) async {
    final cached = _sanitizeMetaCache[table];
    if (cached != null) return cached;

    // Warm the cache with a metadata-only round trip (empty object, keep secrets).
    final response = await _dispatchOperation<SanitizeOperationResponse>(
      SanitizeOperationRequest(
        table: table,
        objects: const [{}],
        preserveSecrets: true,
      ),
    );
    return _sanitizeMetaCache[table] = (
      secretColumns: response.secretColumns,
      photoColumns: response.photoColumns,
    );
  }

  Future<List<_SideEffect>> _getEffect(MutationRequest mut) async {
    switch (mut) {
      case final DeleteRecordRequest mut:
        final (objects, :deleteOperation) = await _deleteOperation(
          mut.table,
          DeletePayload(where: mut.where, limit: mut.limit),
          mut.jwt,
        );

        if (objects.isEmpty) {
          return [];
        }

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
          :refetchOperation,
          :updateOperation,
        ) = await _updateOperation(
          mut.table,
          UpdatePayload(where: mut.where, updates: mut.updates),
          mut.jwt,
        );

        // `refetchOperation` is null exactly when nothing matched, which
        // `objects.isEmpty` already covers -- the check is here so the field
        // below can stay non-nullable rather than defer the question.
        if (objects.isEmpty || refetchOperation == null) {
          return [];
        }

        logger.trace('(SIDE EFFECT) Updating records: ${objects.length}');

        return [
          _UpdateSideEffect(
            request: mut,
            before: objects,
            operation: updateOperation,
            refetchOperation: refetchOperation,
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
      throw const DatabaseNotOpenException();
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
      throw const DatabaseNotOpenException();
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
            final rows = operationResults[effect]?.rows ?? const [];
            final raw = rows.isEmpty ? null : rows.first.toMap();
            if (raw != null) {
              final created = await _sanitizeRow(
                effect.request.table,
                raw,
                jwt: effect.request.jwt,
              );
              await _postCreate(
                effect.request.table,
                effect.request.jwt,
                object: created,
              );
            } else {
              logger.error('(SIDE EFFECT) Unexpected error during create');
            }
          case _UpdateSideEffect(:final refetchOperation):
            // `updateResult.rows` always returns empty, need to refetch the
            // records -- keyed by the ids read before the write, never by
            // replaying the where. See `_refetchOperation`: a `mutate.update`
            // that rewrites the column it matched on would otherwise read back
            // nothing and hand `_postUpdate` a before/after pair of different
            // lengths.
            final (_, updatedResult) = await _execute((
              refetchOperation.query,
              refetchOperation.values,
            ));

            final afterRows = updatedResult?.rows
                .map((e) => e.toMap())
                .toList();

            if (afterRows != null) {
              final after = await _sanitizeRows(
                effect.request.table,
                afterRows,
                jwt: effect.request.jwt,
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
      throw const DatabaseNotOpenException();
    }

    try {
      logger.verbose('Streaming query: $query', prefix: _prefix);
      final stream = _resqlite.streamQuery(query, values);
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
    required this.refetchOperation,
    required this.before,
    required super.operation,
  });

  final PerformOperationResponse refetchOperation;
  final UpdateRecordRequest request;
  final List<Map<String, Object?>> before;
}
