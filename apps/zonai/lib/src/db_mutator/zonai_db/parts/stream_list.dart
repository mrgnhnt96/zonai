part of zonai_db;

extension _StreamListX on ZonaiDb {
  Stream<List<Map<String, Object?>>> _streamList(
    String table,
    ListPayload payload,
  ) async* {
    final jwt = await _extractJwt(payload, allowApiToken: true);
    await _requireTableAccess(table, .list, jwt);

    final operation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: payload.limit,
        offset: payload.offset,
        orderBy: payload.orderBy,
        groupBy: payload.groupBy,
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
    await _requireRowsAccess(table, .view, objects, jwt);

    // Re-checked on EVERY emission, not just the snapshot above.
    //
    // The initial check said nothing about the rows that follow it. A stream
    // opened against a row rule the caller fails matched nothing at first, so
    // `_requireRowsAccess` returned early on the empty list -- no rows, nothing
    // to deny -- and the subscription was then fed every row the query matched
    // from then on, unchecked. An anonymous caller could open a stream on a
    // table whose rule is `row.id == jwt.userId`, see it open quietly, and be
    // handed a full row the moment anyone inserted one.
    //
    // Denied rows are filtered out rather than failing the stream: see
    // [_filterRowsAccess].
    await for (final result in _stream(operation.query, operation.values)) {
      final rows = await _filterRowsAccess(
        table,
        .view,
        result.rows.map((e) => e.toMap()).toList(),
        jwt,
      );

      yield await _expandRows(
        table,
        await _sanitizeRows(table, rows, jwt: jwt),
        payload.expand,
        jwt,
      );
    }
  }
}
