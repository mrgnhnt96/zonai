part of zonai_db;

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

      step = 'sql_execute';
      final (deleteError, deleteResult) = await _execute((
        deleteOperation.query,
        deleteOperation.values,
      ));
      logger.trace('sql_execute_delete');
      if (deleteError != null || deleteResult == null) {
        await _extensions.send<NoActionExtensionResponse>(
          ErrorExtensionRequest.delete(
            table: table,
            error: deleteError?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        throw deleteError ?? RecordDeleteFailedException(table: table);
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
    await _extensions.send<NoActionExtensionResponse>(
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

    final readOperation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: payload.limit,
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
      throw readError ?? RecordReadFailedException(table: table);
    }

    if (readResult.rows.isEmpty) {
      throw RecordNotFoundException(table: table);
    }

    final rows = readResult.rows.map((e) => e.toMap()).toList();
    for (final object in rows) {
      await _requireRowAccess(table, .delete, object, jwt);
    }
    logger.trace('row_access', extra: {'rows': rows.length});

    final sanitized = await _sanitizeRows(table, rows, jwt: jwt);

    await _extensions.send<NoActionExtensionResponse>(
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
