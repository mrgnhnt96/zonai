part of zonai_db;

extension _UpdateX on ZonaiDb {
  Future<_CrudListResult> _update(
    String collection,
    UpdatePayload payload, {
    Jwt? userJwt,
  }) async {
    final jwt = userJwt ?? await _extractJwt(payload);
    final (beforeObjects, :readOperation, :updateOperation) =
        await _updateOperation(collection, payload, jwt);

    final (updateError, updateResult) = await _execute((
      updateOperation.query,
      updateOperation.values,
    ));
    if (updateError != null) {
      throw updateError;
    }

    if (updateResult == null) {
      throw StateError('Failed to update record(s)');
    }

    logger.trace(
      'Updated ${updateResult.rowsAffected} records',
      prefix: _prefix,
    );

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

      throw updatedError ?? StateError('Failed to update record');
    }

    final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();

    final sanitizedUpdated = await _sanitizeRows(collection, updatedObjects);

    await _postUpdate(
      collection,
      jwt,
      before: beforeObjects,
      after: sanitizedUpdated,
    );

    await _executeEffects();

    return sanitizedUpdated;
  }

  Future<void> _postUpdate(
    String collection,
    Jwt? jwt, {
    required List<Map<String, Object?>> before,
    required List<Map<String, Object?>> after,
  }) async {
    await _extensions.send(
      AfterUpdateExtensionRequest(
        collection: collection,
        before: before,
        after: after,
        jwt: jwt,
      ),
    );
  }

  Future<
    (
      List<Map<String, Object?>>, {
      PerformOperationResponse readOperation,
      PerformOperationResponse updateOperation,
    })
  >
  _updateOperation(String collection, UpdatePayload payload, Jwt? jwt) async {
    await _requireCollectionAccess(collection, .update, jwt);

    final readOperation = await _getOperation(
      ListOperationRequest(
        collection: collection,
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
    if (readError != null) {
      throw readError;
    }

    if (readResult == null) {
      throw StateError('Failed to read record(s)');
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      await _requireRecordAccess(collection, .update, row, jwt);
    }

    final sanitizedBefore = await _sanitizeRows(collection, objects);

    await _extensions.send(
      BeforeUpdateExtensionRequest(
        collection: collection,
        objects: sanitizedBefore,
        jwt: jwt,
      ),
    );

    final operation = await _getOperation(
      UpdateOperationRequest(
        collection: collection,
        where: payload.where,
        updates: payload.updates,
        jwt: jwt,
      ),
    );

    return (
      sanitizedBefore,
      readOperation: readOperation,
      updateOperation: operation,
    );
  }
}
