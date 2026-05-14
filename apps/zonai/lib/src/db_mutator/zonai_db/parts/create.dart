part of zonai_db;

extension _CreateX on ZonaiDb {
  Future<_CrudResult> _create(String collection, CreatePayload payload) async {
    final jwt = await _extractJwt(payload);
    await _requireCollectionAccess(collection, .create, jwt);
    await _requireRecordAccess(collection, .create, payload.object, jwt);

    await _extensions.send(
      CreateExtensionRequest.before(
        collection: collection,
        object: payload.object,
        jwt: jwt,
      ),
    );

    final operation = await _getOperation(
      CreateOperationRequest(
        collection: collection,
        object: payload.object,
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      await _extensions.send(
        ErrorExtensionRequest.create(
          collection: collection,
          error: error?.toString() ?? 'Unknown error',
          jwt: jwt,
        ),
      );

      return (error ?? 'Failed', null);
    }

    final created = result.rows.single.toMap();
    logger.verbose('Created: ${created}', prefix: _prefix);

    await _extensions.send(
      CreateExtensionRequest.afterSuccess(
        collection: collection,
        object: created,
        jwt: jwt,
      ),
    );

    return (null, created);
  }
}
