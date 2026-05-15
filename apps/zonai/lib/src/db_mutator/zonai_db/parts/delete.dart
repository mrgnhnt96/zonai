part of zonai_db;

extension _DeleteX on ZonaiDb {
  Future<int> _delete(String collection, DeletePayload payload) async {
    final jwt = await _extractJwt(payload);
    final (objects, :deleteOperation) = await _deleteOperation(
      collection,
      payload,
      jwt,
    );

    final (deleteError, deleteResult) = await _execute((
      deleteOperation.query,
      deleteOperation.values,
    ));
    if (deleteError != null || deleteResult == null) {
      await _extensions.send(
        ErrorExtensionRequest.delete(
          collection: collection,
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

    await _postDelete(collection, jwt, objects: objects);

    await _executeEffects();

    return deleteResult.rowsAffected;
  }

  Future<void> _postDelete(
    String collection,
    Jwt? jwt, {
    required List<Map<String, Object?>> objects,
  }) async {
    await _extensions.send(
      DeleteExtensionRequest.afterSuccess(
        collection: collection,
        objects: objects,
        jwt: jwt,
      ),
    );
  }

  Future<
    (List<Map<String, Object?>>, {PerformOperationResponse deleteOperation})
  >
  _deleteOperation(String collection, DeletePayload payload, Jwt? jwt) async {
    await _requireCollectionAccess(collection, .delete, jwt);

    final where = payload.where.sql(collection);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: where,
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
      await _requireRecordAccess(collection, .delete, object, jwt);
    }

    final sanitized = await _sanitizeRows(collection, rows);

    await _extensions.send(
      DeleteExtensionRequest.before(
        collection: collection,
        objects: sanitized,
        jwt: jwt,
      ),
    );

    final deleteOperation = await _getOperation(
      DeleteOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
        jwt: jwt,
      ),
    );

    return (sanitized, deleteOperation: deleteOperation);
  }
}
