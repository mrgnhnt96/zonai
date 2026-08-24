part of zonai_db;

/// Whether [sql] is a statement that modifies data.
///
/// Used to decide whether a custom operation needs row rules run over it, for
/// the case where nothing else says so: a `custom` override returns an opaque
/// query, and `customUpdates` — the declaration that would have said — is
/// documented as easy to forget and defaults to echoing the caller's updates.
///
/// Reads the leading keyword only, and treats anything it does not recognise
/// as a write. Guessing "read" for an unfamiliar statement is the answer that
/// skips the check.
bool _statementWrites(String sql) {
  final trimmed = sql.trimLeft();
  if (trimmed.isEmpty) return false;

  // `WITH` is deliberately absent: a common table expression is a perfectly
  // ordinary way to spell `WITH x AS (…) DELETE FROM …`, so its leading
  // keyword says nothing about whether the statement writes.
  final keyword = trimmed.split(RegExp(r'[\s(;]')).first.toUpperCase();
  return switch (keyword) {
    'SELECT' || 'VALUES' || 'EXPLAIN' => false,
    _ => true,
  };
}

extension _CustomX on ZonaiDb {
  Future<_CrudListResult> _custom(String table, CustomPayload payload) async {
    logger.setTraceProps({
      'op': 'custom',
      'table': table,
      'operation': payload.operation,
    });
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload, allowApiToken: true);
      logger.trace('jwt_extract');

      step = 'custom_operation';
      final (beforeObjects, :readOperation, :customOperation) =
          await _customOperationBuild(table, payload, jwt);
      logger.trace('sql_build');

      step = 'sql_execute_custom';
      final (customError, customResult) = await _execute((
        customOperation.query,
        customOperation.values,
      ));
      logger.trace('sql_execute_custom');
      if (customError != null) {
        _throwDatabaseError(
          customError,
          table: table,
          failure: ([cause]) =>
              RecordUpdateFailedException(table: table, cause: cause),
        );
      }

      if (customResult == null) {
        throw RecordUpdateFailedException(table: table);
      }

      // Table-scoped custom operations (no `where`) have no target rows to
      // refetch or sanitize.
      if (readOperation == null) {
        step = 'effects';
        await _executeEffects();
        logger.trace('done');
        return const [];
      }

      // `customResult.rows` can't be relied on the same way `RETURNING`
      // would be — refetch, same as `_update`'s post-write read.
      step = 'sql_execute_refetch';
      final (updatedError, updatedResult) = await _execute((
        readOperation.query,
        readOperation.values,
      ));
      logger.trace(
        'sql_execute_refetch',
        extra: {'rows': updatedResult?.rows.length ?? 0},
      );
      if (updatedError != null || updatedResult == null) {
        _throwDatabaseError(
          updatedError,
          table: table,
          failure: ([cause]) =>
              RecordUpdateFailedException(table: table, cause: cause),
        );
      }

      final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();

      step = 'sanitize';
      final sanitizedUpdated = await _sanitizeRows(
        table,
        updatedObjects,
        jwt: jwt,
      );
      logger.trace('sanitize');

      step = 'ext_after';
      await _postUpdate(
        table,
        jwt,
        before: beforeObjects,
        after: sanitizedUpdated,
      );
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done', extra: {'rows': sanitizedUpdated.length});

      return sanitizedUpdated;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<
    (
      List<Map<String, Object?>>, {
      PerformOperationResponse? readOperation,
      PerformOperationResponse customOperation,
    })
  >
  _customOperationBuild(String table, CustomPayload payload, Jwt? jwt) async {
    if (payload.updates.isNotEmpty && payload.where == null) {
      throw CustomOperationRequiresWhereException(
        table: table,
        operation: payload.operation,
      );
    }

    // A custom operation may not be named after a classic verb. Such a name
    // resolves to the built-in rule (`RuleRequest.classicOperation`), so the
    // call would be adjudicated by `canUpdate`/`canView`/... while the author's
    // `customOperations['update']` entry sat unread. `DbRules` refuses to
    // register the collision; refusing it here too means a caller cannot reach
    // the ambiguity from the wire even on a table that registered no rule of
    // that name at all -- which is the shape that used to 500.
    if (TableOperation.fromString(payload.operation) != null ||
        RowOperation.fromString(payload.operation) != null) {
      throw CustomOperationNameCollisionException(
        table: table,
        operation: payload.operation,
      );
    }

    await _requireCustomTableAccess(table, payload.operation, jwt);
    logger.trace('table_access');

    // No `where` — a table-scoped action (e.g. an administrative operation)
    // with no specific row to check or refetch.
    if (payload.where == null) {
      final customOperation = await _getOperation(
        CustomOperationRequest(
          table: table,
          operation: payload.operation,
          where: null,
          updates: payload.updates,
          jwt: jwt,
        ),
      );

      // The guard at the top of this method catches a *caller* who sent
      // updates without a `where`. It cannot catch the more dangerous shape:
      // an operation whose writes are the server's own, which the caller
      // invokes with no updates and no `where` at all. That reached here with
      // row rules never consulted -- the permissive table rule alone
      // authorizing a write across the whole table.
      //
      // The compiled statement is the one thing that cannot lie about whether
      // it writes, so it is what gets asked. `customUpdates` is consulted too,
      // for an operation that declares writes it performs some other way.
      if (customOperation.updates.isNotEmpty ||
          _statementWrites(customOperation.query)) {
        throw CustomOperationRequiresWhereException(
          table: table,
          operation: payload.operation,
        );
      }

      return (
        const <Map<String, Object?>>[],
        readOperation: null,
        customOperation: customOperation,
      );
    }

    final readOperation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: payload.limit,
        offset: null,
        jwt: jwt,
      ),
    );

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    logger.trace(
      'sql_execute_read',
      extra: {'rows': readResult?.rows.length ?? 0},
    );
    if (readError != null) {
      _throwDatabaseError(
        readError,
        table: table,
        failure: ([cause]) =>
            RecordReadFailedException(table: table, cause: cause),
      );
    }

    if (readResult == null) {
      throw RecordReadFailedException(table: table);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    // Resolved BEFORE the row checks, not after, and the order is the fix.
    //
    // A row rule decides whether the *resulting* row is allowed, and the
    // resulting row is computed by replaying updates over the row that was
    // read. For a custom operation those updates are the server's own — the
    // caller may legitimately send none — so checking first meant every such
    // rule adjudicated a row identical to `before`: a mutation the server was
    // about to perform correctly, refused on the strength of a row that was
    // never going to be written.
    //
    // Resolving early is safe because this only compiles the query. Nothing
    // executes until the caller runs it, well after these checks pass.
    //
    // Built against the ids just read rather than `payload.where`, for the
    // reason given in [_authorizedRowsWhere]: the rows checked below are the
    // rows this statement must be able to touch, and no others. The two clauses
    // select the same set here, so an operation reading its `where` sees the
    // same rows -- it just can no longer widen between the read and the write.
    final authorizedWhere = await _authorizedRowsWhere(table, objects);
    final customOperation = await _getOperation(
      CustomOperationRequest(
        table: table,
        operation: payload.operation,
        where: authorizedWhere,
        updates: payload.updates,
        jwt: jwt,
      ),
    );

    for (final row in objects) {
      await _requireCustomRowAccess(
        table,
        payload.operation,
        row,
        jwt,
        // `customUpdates` defaults to echoing the caller's updates, so an
        // operation that only reshapes what it was handed is unchanged by this.
        updates: customOperation.updates,
      );
    }
    logger.trace('row_access');

    final sanitizedBefore = await _sanitizeRows(table, objects, jwt: jwt);

    return (
      sanitizedBefore,
      readOperation: readOperation,
      customOperation: customOperation,
    );
  }
}
