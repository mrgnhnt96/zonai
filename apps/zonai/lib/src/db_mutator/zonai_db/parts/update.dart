part of zonai_db;

extension _UpdateX on ZonaiDb {
  Future<_CrudListResult> _update(
    String collection,
    UpdatePayload payload,
  ) async {
    final jwt = _extractJwt(payload);
    await _requireCollectionAccess(collection, .update);

    final where = payload.where.sql(collection);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
        offset: null,
      ),
    );

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    if (readError != null || readResult == null) {
      return (readError ?? 'Failed', null);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      await _requireRecordAccess(collection, .update, row);
    }

    {
      final beforeUpdate = await _extensions.send(
        BeforeUpdateExtensionRequest(collection: collection, objects: objects),
      );
    }

    final updateOperation = await _getOperation(
      UpdateOperationRequest(
        collection: collection,
        where: where,
        updates: payload.updates,
      ),
    );

    final (updateError, updateResult) = await _execute((
      updateOperation.query,
      updateOperation.values,
    ));
    if (updateError != null || updateResult == null) {
      return (updateError ?? 'Failed', null);
    }

    logger.verbose('Updated: ${updateResult}', prefix: _prefix);

    // `updateResult.rows` always returns empty, need to refetch the records
    final (updatedError, updatedResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    if (updatedError != null || updatedResult == null) {
      final afterUpdate = await _extensions.send(
        ErrorExtensionRequest.update(
          collection: collection,
          error: updatedError?.toString() ?? 'Unknown error',
        ),
      );

      return (updatedError ?? 'Failed', null);
    }

    final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();
    logger.verbose('Updated objects: ${updatedObjects}', prefix: _prefix);

    {
      final afterUpdate = await _extensions.send(
        AfterUpdateExtensionRequest(
          collection: collection,
          before: objects,
          after: updatedObjects,
        ),
      );
    }

    return (null, updatedObjects);
  }
}
