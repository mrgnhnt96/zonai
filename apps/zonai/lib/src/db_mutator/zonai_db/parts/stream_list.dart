part of zonai_db;

extension _StreamListX on ZonaiDb {
  Stream<List<Map<String, Object?>>> _streamList(
    String collection,
    ListPayload payload,
  ) async* {
    final jwt = await _extractJwt(payload);
    await _requireCollectionAccess(collection, .list, jwt);

    final where = payload.where?.sql(collection);
    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: where,
        limit: payload.limit,
        offset: payload.offset,
        jwt: jwt,
      ),
    );

    final (readError, readResult) = await _execute((
      operation.query,
      operation.values,
    ));
    if (readError != null || readResult == null) {
      throw StateError('Failed to read records: $readError');
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();
    for (final object in objects) {
      await _requireRecordAccess(collection, .view, object, jwt);
    }

    await for (final result in _stream(operation.query, operation.values)) {
      yield await _sanitizeRows(
        collection,
        result.rows.map((e) => e.toMap()).toList(),
      );
    }
  }
}
