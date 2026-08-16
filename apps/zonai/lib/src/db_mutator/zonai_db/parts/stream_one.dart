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
      throw RecordReadFailedException(table: table, cause: readError);
    }

    final object = readResult.rows.single.toMap();
    await _requireRowAccess(table, .view, object, jwt);

    // Re-checked on every emission, for the reason given in [_streamList]: the
    // check above covers the row as it was when the stream opened, and this
    // stream stays open across writes to it. A row edited into a state this
    // caller may no longer view -- reassigned to another owner, unpublished --
    // would otherwise keep arriving on a subscription authorized against the
    // version before the edit.
    //
    // This one denies rather than filters: a single-record stream has no
    // "some rows" to fall back to, so the honest outcome is to stop.
    await for (final result in _stream(operation.query, operation.values)) {
      if (result.rows.isEmpty) {
        throw RecordDeletedWhileStreamingException(table: table);
      }
      final row = result.rows.single.toMap();
      await _requireRowAccess(table, .view, row, jwt);

      final sanitized = await _sanitizeRow(table, row, jwt: jwt);
      yield await _expandRow(table, sanitized, payload.expand, jwt);
    }
  }
}
