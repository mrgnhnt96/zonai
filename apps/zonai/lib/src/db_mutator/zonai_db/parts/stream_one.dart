part of zonai_db;

extension _StreamOneX on ZonaiDb {
  Stream<Map<String, Object?>> _streamOne(
    String table,
    ViewPayload payload,
  ) async* {
    final jwt = await _extractJwt(payload);
    await _requireTableAccess(table, .view, jwt);

    final operation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: 1,
        offset: null,
        jwt: jwt,
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
    await _requireRowAccess(table, .view, object, jwt);

    await for (final result in _stream(operation.query, operation.values)) {
      if (result.rows.isEmpty) {
        throw StateError('No record found or record was deleted');
      }
      final sanitized = await _sanitizeRow(
        table,
        result.rows.single.toMap(),
      );
      yield await _expandRow(table, sanitized, payload.expand, jwt);
    }
  }
}
