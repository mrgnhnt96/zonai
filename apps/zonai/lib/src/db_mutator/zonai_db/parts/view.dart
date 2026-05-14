part of zonai_db;

extension _ViewX on ZonaiDb {
  Future<_CrudResult> _view(String collection, ViewPayload payload) async {
    final jwt = await _extractJwt(payload);
    await _requireCollectionAccess(collection, .view, jwt);

    final operation = await _getOperation(
      ViewOperationRequest(
        collection: collection,
        where: payload.where.sql(collection),
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    if (result.rows.isEmpty) {
      return (null, null);
    }

    final object = result.rows.first.toMap();
    logger.verbose('Found object: ${object}', prefix: _prefix);

    await _requireRecordAccess(collection, .view, object, jwt);

    return (null, object);
  }
}
