part of zonai_db;

extension _UpdateX on ZonaiDb {
  Future<_CrudListResult> _update(
    String table,
    UpdatePayload payload, {
    Jwt? userJwt,
  }) async {
    final jwt = userJwt ?? await _extractJwt(payload);
    final (beforeObjects, :readOperation, :updateOperation) =
        await _updateOperation(table, payload, jwt);

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
      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.update(
          table: table,
          error: updatedError?.toString() ?? 'Unknown error',
          jwt: jwt,
        ),
      );

      throw updatedError ?? StateError('Failed to update record');
    }

    final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();

    final sanitizedUpdated = await _sanitizeRows(
      table,
      updatedObjects,
      jwt: jwt,
    );

    await _postUpdate(
      table,
      jwt,
      before: beforeObjects,
      after: sanitizedUpdated,
    );

    await _executeEffects();

    return sanitizedUpdated;
  }

  Future<void> _postUpdate(
    String table,
    Jwt? jwt, {
    required List<Map<String, Object?>> before,
    required List<Map<String, Object?>> after,
  }) async {
    await _extensions.send<NoActionExtensionResponse>(
      AfterUpdateExtensionRequest(
        table: table,
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
  _updateOperation(String table, UpdatePayload payload, Jwt? jwt) async {
    await _requireTableAccess(table, .update, jwt);

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
    if (readError != null) {
      throw readError;
    }

    if (readResult == null) {
      throw StateError('Failed to read record(s)');
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      await _requireRowAccess(table, .update, row, jwt);
    }

    final sanitizedBefore = await _sanitizeRows(table, objects, jwt: jwt);

    await _requirePhotoReferencesFromUpdates(table, payload.updates);

    await _extensions.send<NoActionExtensionResponse>(
      BeforeUpdateExtensionRequest(
        table: table,
        objects: sanitizedBefore,
        jwt: jwt,
      ),
    );

    final operation = await _getOperation(
      UpdateOperationRequest(
        table: table,
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
