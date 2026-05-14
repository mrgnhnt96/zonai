part of zonai_db;

extension _UpdateX on ZonaiDb {
  Future<_CrudListResult> _update(
    String collection,
    UpdatePayload payload,
  ) async {
    final jwt = await _extractJwt(payload);
    await _requireCollectionAccess(collection, .update, jwt);

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

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    if (readError != null || readResult == null) {
      return (readError ?? 'Failed', null);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      await _requireRecordAccess(collection, .update, row, jwt);
    }

    await _extensions.send(
      BeforeUpdateExtensionRequest(
        collection: collection,
        objects: objects,
        jwt: jwt,
      ),
    );

    final updateOperation = await _getOperation(
      UpdateOperationRequest(
        collection: collection,
        where: where,
        updates: payload.updates,
        jwt: jwt,
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
      await _extensions.send(
        ErrorExtensionRequest.update(
          collection: collection,
          error: updatedError?.toString() ?? 'Unknown error',
          jwt: jwt,
        ),
      );

      return (updatedError ?? 'Failed', null);
    }

    final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();
    logger.verbose('Updated objects: ${updatedObjects}', prefix: _prefix);

    await _extensions.send(
      AfterUpdateExtensionRequest(
        collection: collection,
        before: objects,
        after: updatedObjects,
        jwt: jwt,
      ),
    );

    return (null, updatedObjects);
  }
}
