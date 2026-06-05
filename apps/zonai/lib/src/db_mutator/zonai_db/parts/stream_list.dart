part of zonai_db;

extension _StreamListX on ZonaiDb {
  Stream<List<Map<String, Object?>>> _streamList(
    String table,
    ListPayload payload,
  ) async* {
    final jwt = await _extractJwt(payload);
    await _requireTableAccess(table, .list, jwt);

    final operation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: payload.limit,
        offset: payload.offset,
        orderBy: payload.orderBy,
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
      await _requireRowAccess(table, .view, object, jwt);
    }

    await for (final result in _stream(operation.query, operation.values)) {
      yield await _expandRows(
        table,
        await _sanitizeRows(
          table,
          result.rows.map((e) => e.toMap()).toList(),
          jwt: jwt,
        ),
        payload.expand,
        jwt,
      );
    }
  }
}
