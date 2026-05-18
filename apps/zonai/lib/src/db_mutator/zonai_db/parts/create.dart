part of zonai_db;

extension _CreateX on ZonaiDb {
  Future<_CrudResult> _create(String collection, CreatePayload payload) async {
    final jwt = await _extractJwt(payload);
    await _requireCollectionAccess(collection, .create, jwt);
    final operation = await _createOperation(collection, payload, jwt);

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      await _extensions.send(
        ErrorExtensionRequest.create(
          collection: collection,
          error: error?.toString() ?? 'Unknown error',
          jwt: jwt,
        ),
      );

      throw error ?? StateError('Failed to create record');
    }

    final created = await _sanitizeRow(collection, result.rows.single.toMap());

    await _postCreate(collection, jwt, object: created);

    await _executeEffects();

    return created;
  }

  // TODO: add failed
  Future<void> _postCreate(
    String collection,
    Jwt? jwt, {
    required Map<String, Object?> object,
  }) async {
    await _extensions.send(
      CreateExtensionRequest.afterSuccess(
        collection: collection,
        object: object,
        jwt: jwt,
      ),
    );
  }

  Future<PerformOperationResponse> _createOperation(
    String collection,
    CreatePayload payload,
    Jwt? jwt,
  ) async {
    await _requireRecordAccess(collection, .create, payload.object, jwt);

    await _extensions.send(
      CreateExtensionRequest.before(
        collection: collection,
        object: payload.object,
        jwt: jwt,
      ),
    );

    return await _getOperation(
      CreateOperationRequest(
        collection: collection,
        object: payload.object,
        jwt: jwt,
      ),
    );
  }
}
