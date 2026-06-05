part of zonai_db;

extension _DeleteX on ZonaiDb {
  Future<int> _delete(String table, DeletePayload payload) async {
    final jwt = await _extractJwt(payload);
    final (objects, :deleteOperation) = await _deleteOperation(
      table,
      payload,
      jwt,
    );

    final (deleteError, deleteResult) = await _execute((
      deleteOperation.query,
      deleteOperation.values,
    ));
    if (deleteError != null || deleteResult == null) {
      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.delete(
          table: table,
          error: deleteError?.toString() ?? 'Unknown error',
          jwt: jwt,
        ),
      );

      throw deleteError ?? StateError('Failed to delete record(s)');
    }

    logger.trace(
      'Deleted ${deleteResult.rowsAffected} records',
      prefix: _prefix,
    );

    await _postDelete(table, jwt, objects: objects);

    await _executeEffects();

    return deleteResult.rowsAffected;
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
    if (readError != null || readResult == null) {
      throw readError ?? StateError('Failed to read record');
    }

    if (readResult.rows.isEmpty) {
      throw StateError('Record not found');
    }

    final rows = readResult.rows.map((e) => e.toMap()).toList();
    for (final object in rows) {
      await _requireRowAccess(table, .delete, object, jwt);
    }

    final sanitized = await _sanitizeRows(table, rows, jwt: jwt);

    await _extensions.send<NoActionExtensionResponse>(
      DeleteExtensionRequest.before(
        table: table,
        objects: sanitized,
        jwt: jwt,
      ),
    );

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
