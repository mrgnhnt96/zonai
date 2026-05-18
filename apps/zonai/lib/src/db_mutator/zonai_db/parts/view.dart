part of zonai_db;

extension _ViewX on ZonaiDb {
  Future<_CrudResult> _view(
    String collection,
    ViewPayload payload, {
    Jwt? userJwt,
  }) async {
    final jwt = userJwt ?? await _extractJwt(payload);
    await _requireCollectionAccess(collection, .view, jwt);

    final operation = await _getOperation(
      ViewOperationRequest(
        collection: collection,
        where: payload.where,
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to read record');
    }

    if (result.rows.isEmpty) {
      throw StateError('Record not found');
    }

    final object = result.rows.first.toMap();
    logger.verbose('Found object: ${object}', prefix: _prefix);

    await _requireRecordAccess(collection, .view, object, jwt);

    return await _sanitizeRow(collection, object);
  }
}
