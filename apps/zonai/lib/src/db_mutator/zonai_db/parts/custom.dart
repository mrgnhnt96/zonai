part of zonai_db;

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
      final jwt = await _extractJwt(payload);
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
    final customOperation = await _getOperation(
      CustomOperationRequest(
        table: table,
        operation: payload.operation,
        where: payload.where,
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
