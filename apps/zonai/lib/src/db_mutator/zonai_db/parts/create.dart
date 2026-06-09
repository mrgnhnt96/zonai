part of zonai_db;

extension _CreateX on ZonaiDb {
  Future<_CrudResult> _create(String table, CreatePayload payload) async {
    logger.setTraceProps({'op': 'create', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireTableAccess(table, .create, jwt);
      logger.trace('table_access');

      step = 'create_operation';
      final operation = await _createOperation(table, payload, jwt);
      logger.trace('sql_build');

      step = 'sql_execute';
      final (error, result) = await _execute((operation.query, operation.values));
      logger.trace('sql_execute');
      if (error != null || result == null) {
        await _extensions.send<NoActionExtensionResponse>(
          ErrorExtensionRequest.create(
            table: table,
            error: error?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        throw error ?? RecordCreateFailedException(table: table);
      }

      step = 'sanitize';
      final created = await _sanitizeRow(table, result.rows.single.toMap());
      logger.trace('sanitize');

      step = 'ext_after';
      await _postCreate(table, jwt, object: created);
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return created;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
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
    logger.trace('row_access');

    await _requirePhotoReferences(table, payload.object);
    logger.trace('photo_refs');

    await _extensions.send<NoActionExtensionResponse>(
      CreateExtensionRequest.before(
        table: table,
        object: payload.object,
        jwt: jwt,
      ),
    );
    logger.trace('ext_before');

    return await _getOperation(
      CreateOperationRequest(table: table, object: payload.object, jwt: jwt),
    );
  }
}
