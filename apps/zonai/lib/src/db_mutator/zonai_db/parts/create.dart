part of zonai_db;

extension _CreateX on ZonaiDb {
  Future<_CrudResult> _create(String table, CreatePayload payload) async {
    final jwt = await _extractJwt(payload);
    await _requireTableAccess(table, .create, jwt);
    final operation = await _createOperation(table, payload, jwt);

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.create(
          table: table,
          error: error?.toString() ?? 'Unknown error',
          jwt: jwt,
        ),
      );

      throw error ?? StateError('Failed to create record');
    }

    final created = await _sanitizeRow(table, result.rows.single.toMap());

    await _postCreate(table, jwt, object: created);

    await _executeEffects();

    return created;
  }

  // TODO: add failed
  Future<void> _postCreate(
    String table,
    Jwt? jwt, {
    required Map<String, Object?> object,
  }) async {
    await _extensions.send<NoActionExtensionResponse>(
      CreateExtensionRequest.afterSuccess(
        table: table,
        object: object,
        jwt: jwt,
      ),
    );
  }

  Future<PerformOperationResponse> _createOperation(
    String table,
    CreatePayload payload,
    Jwt? jwt,
  ) async {
    await _requireRowAccess(table, .create, payload.object, jwt);
    await _requirePhotoReferences(table, payload.object);

    await _extensions.send<NoActionExtensionResponse>(
      CreateExtensionRequest.before(
        table: table,
        object: payload.object,
        jwt: jwt,
      ),
    );

    return await _getOperation(
      CreateOperationRequest(table: table, object: payload.object, jwt: jwt),
    );
  }
}
