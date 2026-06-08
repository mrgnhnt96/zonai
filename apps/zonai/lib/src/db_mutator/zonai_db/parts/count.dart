part of zonai_db;

extension _CountX on ZonaiDb {
  Future<int> _count(String table, CountPayload payload, {Jwt? userJwt}) async {
    final jwt = userJwt ?? await _extractJwt(payload);
    await _requireTableAccess(table, .list, jwt);

    final operation = await _getOperation(
      CountOperationRequest(table: table, where: payload.where, jwt: jwt),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? RecordCountFailedException(table: table);
    }

    return _countFromResult(result);
  }

  Stream<int> _streamCount(String table, CountPayload payload) async* {
    final jwt = await _extractJwt(payload);
    await _requireTableAccess(table, .list, jwt);

    final operation = await _getOperation(
      CountOperationRequest(table: table, where: payload.where, jwt: jwt),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? RecordCountFailedException(table: table);
    }

    final stream = _stream(operation.query, operation.values);
    // only yield counts when the count changes
    await for (final result in stream.distinct()) {
      yield _countFromResult(result);
    }
  }
}

int _countFromResult(OperationResult result) {
  if (result.rows.isEmpty) return 0;
  final values = result.rows.first.values;
  if (values.isEmpty) return 0;
  final value = values.first;
  return switch (value) {
    final int v => v,
    final BigInt v => v.toInt(),
    final double v => v.toInt(),
    _ => 0,
  };
}
