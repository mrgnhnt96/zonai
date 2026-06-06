part of zonai_db;

extension _ReadX on ZonaiDb {
  Future<_CrudResult> _read(
    String table,
    ViewPayload payload, {
    Jwt? userJwt,
  }) async {
    final jwt = userJwt ?? await _extractJwt(payload);
    await _requireTableAccess(table, .view, jwt);

    final operation = await _getOperation(
      ReadOperationRequest(table: table, where: payload.where, jwt: jwt),
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

    await _requireRowAccess(table, .view, object, jwt);

    final sanitized = await _sanitizeRow(table, object, jwt: jwt);
    return await _expandRow(table, sanitized, payload.expand, jwt);
  }
}
