part of zonai_db;

extension _CreateX on ZonaiDb {
  Future<_CrudResult> _create(String collection, CreatePayload payload) async {
    final jwt = _extractJwt(payload);
    await _requireCollectionAccess(collection, .create);
    await _requireRecordAccess(collection, .create, payload.object);

    {
      final beforeCreate = await _extensions.send(
        CreateExtensionRequest.before(
          collection: collection,
          object: payload.object,
        ),
      );
    }

    final operation = await _getOperation(
      CreateOperationRequest(collection: collection, object: payload.object),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      final afterCreate = await _extensions.send(
        ErrorExtensionRequest.create(
          collection: collection,

          error: error?.toString() ?? 'Unknown error',
        ),
      );

      return (error ?? 'Failed', null);
    }

    final created = result.rows.single.toMap();
    logger.verbose('Created: ${created}', prefix: _prefix);

    {
      final afterCreate = await _extensions.send(
        CreateExtensionRequest.afterSuccess(
          collection: collection,
          object: payload.object,
        ),
      );
    }

    return (null, created);
  }
}
