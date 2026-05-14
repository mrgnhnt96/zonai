part of zonai_db;

extension _ListX on ZonaiDb {
  Future<_CrudListResult> _list(
    String collection,
    ListPayload payload, {
    Jwt? userJwt,
  }) async {
    final jwt = userJwt ?? await _extractJwt(payload);
    await _requireCollectionAccess(collection, .list, jwt);

    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where?.sql(collection),
        limit: payload.limit,
        offset: payload.offset,
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to list records');
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.verbose('Found ${objects.length} objects', prefix: _prefix);

    for (final object in objects) {
      await _requireRecordAccess(collection, .view, object, jwt);
    }

    return objects;
  }
}
