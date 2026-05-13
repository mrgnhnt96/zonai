part of zonai_db;

extension _DeleteX on ZonaiDb {
  Future<_Result<int>> _delete(String collection, DeletePayload payload) async {
    final jwt = _extractJwt(payload);
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
}
