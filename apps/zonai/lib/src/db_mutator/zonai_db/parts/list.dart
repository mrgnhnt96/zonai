part of zonai_db;

extension _ListX on ZonaiDb {
  Future<_CrudListResult> _list(String collection, ListPayload payload) async {
    final jwt = _extractJwt(payload);
    await _requireCollectionAccess(collection, .list);

    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where?.sql(collection),
        limit: payload.limit,
        offset: payload.offset,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      return (error ?? 'Failed', null);
    }

    final objects = result.rows.map((e) => e.toMap()).toList();
    logger.verbose('Found ${objects.length} objects', prefix: _prefix);

    for (final object in objects) {
      await _requireRecordAccess(collection, .view, object);
    }

    return (null, objects);
  }
}
