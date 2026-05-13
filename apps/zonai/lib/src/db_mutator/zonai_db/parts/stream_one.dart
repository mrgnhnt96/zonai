part of zonai_db;

extension _StreamOneX on ZonaiDb {
  Stream<Map<String, Object?>> _streamOne(
    String collection,
    ViewPayload payload,
  ) async* {
    final jwt = _extractJwt(payload);
    await _requireCollectionAccess(collection, .view);

    final operation = await _getOperation(
      ListOperationRequest(
        collection: collection,
        where: payload.where.sql(collection),
        limit: 1,
        offset: null,
      ),
    );

    final (readError, readResult) = await _execute((
      operation.query,
      operation.values,
    ));
    if (readError != null || readResult == null) {
      throw StateError('Failed to read record: $readError');
    }

    final object = readResult.rows.single.toMap();
    await _requireRecordAccess(collection, .view, object);

    await for (final result in _stream(operation.query, operation.values)) {
      yield result.rows.single.toMap();
    }
  }
}
