part of zonai_db;

/// How many rows a single `delete` may match before it is refused.
///
/// [_deleteOperation] reads every row it is about to remove, so that it can
/// run row rules over them and hand them to `before`/`after` extension hooks.
/// That read is bounded by nothing but the `where` clause, and the rows are
/// all held at once. Past some size the call stops being slow and starts
/// being fatal: a retention sweep over a few million rows exhausts memory on a
/// small host and takes the process with it, which is what a production
/// deployment hit (2026-08-13) once its retention finally ran.
///
/// The number is chosen to sit far above any interactive delete and far below
/// the size that kills a modest server. It is a backstop, not a quota — the
/// point is that the failure is legible and survivable instead of an OOM with
/// nothing in the log.
///
/// Zonai's own retention jobs do not come through here at all; they use
/// [_purge], which deletes in one statement without reading anything back.
const _maxRowsPerDelete = 50000;

extension _DeleteX on ZonaiDb {
  Future<int> _delete(String table, DeletePayload payload) async {
    logger.setTraceProps({'op': 'delete', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'delete_operation';
      final (objects, :deleteOperation) = await _deleteOperation(
        table,
        payload,
        jwt,
      );
      logger.trace('sql_build');

      if (objects.isEmpty) {
        logger.verbose('No records to delete', prefix: _prefix);
        step = 'effects';
        await _executeEffects();
        logger.trace('done', extra: {'rows': 0});
        return 0;
      }

      step = 'sql_execute';
      final (deleteError, deleteResult) = await _execute((
        deleteOperation.query,
        deleteOperation.values,
      ));
      logger.trace('sql_execute_delete');
      if (deleteError != null || deleteResult == null) {
        await _runExtension(
          ErrorExtensionRequest.delete(
            table: table,
            error: deleteError?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        _throwDatabaseError(
          deleteError,
          table: table,
          failure: ([cause]) => RecordDeleteFailedException(table: table, cause: cause),
        );
      }

      logger.verbose(
        'Deleted ${deleteResult.rowsAffected} records',
        prefix: _prefix,
      );

      step = 'ext_after';
      await _postDelete(table, jwt, objects: objects);
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done', extra: {'rows': deleteResult.rowsAffected});

      return deleteResult.rowsAffected;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<void> _postDelete(
    String table,
    Jwt? jwt, {
    required List<Map<String, Object?>> objects,
  }) async {
    await _runExtension(
      DeleteExtensionRequest.afterSuccess(
        table: table,
        objects: objects,
        jwt: jwt,
      ),
    );
  }

  Future<
    (List<Map<String, Object?>>, {PerformOperationResponse deleteOperation})
  >
  _deleteOperation(String table, DeletePayload payload, Jwt? jwt) async {
    await _requireTableAccess(table, .delete, jwt);
    logger.trace('table_access');

    // Never read more than one past the cap. The extra row is what makes
    // "too many" detectable without materializing the set that would prove
    // it. An explicit `limit` is clamped rather than trusted: a caller asking
    // for ten million rows exhausts memory exactly as an unbounded one does,
    // so the bound cannot come from the caller.
    // Spelled out rather than via `min`: the raindrop barrel exports a `min`
    // of its own (the SQL aggregate), which silently wins here.
    const readCeiling = _maxRowsPerDelete + 1;
    final requested = payload.limit;
    final readLimit = (requested == null || requested > readCeiling)
        ? readCeiling
        : requested;

    final readOperation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: readLimit,
        offset: null,
        jwt: jwt,
      ),
    );

    logger.verbose('Read operation: ${readOperation.query}', prefix: _prefix);

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    logger.trace('sql_execute_read', extra: {'rows': readResult?.rows.length ?? 0});
    if (readError != null || readResult == null) {
      _throwDatabaseError(
        readError,
        table: table,
        failure: ([cause]) => RecordReadFailedException(table: table, cause: cause),
      );
    }

    if (readResult.rows.isEmpty) {
      if (payload.limit == 1) {
        throw RecordNotFoundException(table: table);
      }

      final deleteOperation = await _getOperation(
        DeleteOperationRequest(
          table: table,
          where: payload.where,
          limit: payload.limit,
          jwt: jwt,
        ),
      );

      return (<Map<String, Object?>>[], deleteOperation: deleteOperation);
    }

    if (readResult.rows.length > _maxRowsPerDelete) {
      throw RecordDeleteFailedException(
        table: table,
        cause:
            'This delete matches more than $_maxRowsPerDelete rows in "$table". '
            'Deleting reads every matched row first, to run row rules and '
            'extension hooks over it, so a delete this large would exhaust '
            'memory rather than finish. Delete in batches of at most '
            '$_maxRowsPerDelete and repeat until the table is drained.',
      );
    }

    final rows = readResult.rows.map((e) => e.toMap()).toList();
    // Batched: one rules round-trip for the page rather than one per row.
    // The read paths have always used this; the delete path was still doing
    // an awaited dispatch inside a loop, which is what made a large delete
    // slow long before it became fatal.
    await _requireRowsAccess(table, .delete, rows, jwt);
    logger.trace('row_access', extra: {'rows': rows.length});

    final sanitized = await _sanitizeRows(table, rows, jwt: jwt);

    await _runExtension(
      DeleteExtensionRequest.before(table: table, objects: sanitized, jwt: jwt),
    );
    logger.trace('ext_before');

    if (table == '_photos') {
      for (final object in sanitized) {
        if (object case {'path': final String path}) {
          await _deletePhotoFile(path);
        }
      }
      logger.trace('photo_file_delete');
    }

    final deleteOperation = await _getOperation(
      DeleteOperationRequest(
        table: table,
        where: payload.where,
        limit: payload.limit,
        jwt: jwt,
      ),
    );

    return (sanitized, deleteOperation: deleteOperation);
  }
}
