part of zonai_db;

extension _ReadX on ZonaiDb {
  Future<_CrudResult> _read(
    String table,
    ViewPayload payload, {
    Jwt? userJwt,
  }) async {
    logger.setTraceProps({'op': 'read', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = userJwt ?? await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireTableAccess(table, .view, jwt);
      logger.trace('table_access');

      step = 'sql_build';
      final operation = await _getOperation(
        ReadOperationRequest(table: table, where: payload.where, jwt: jwt),
      );
      logger.trace('sql_build');

      step = 'sql_execute';
      final (error, result) = await _execute((operation.query, operation.values));
      logger.trace('sql_execute');
      if (error != null || result == null) {
        throw error ?? RecordReadFailedException(table: table);
      }

      if (result.rows.isEmpty) {
        throw RecordNotFoundException(table: table);
      }

      final object = result.rows.first.toMap();
      logger.verbose('Found object: ${object}', prefix: _prefix);

      step = 'row_access';
      await _requireRowAccess(table, .view, object, jwt);
      logger.trace('row_access');

      step = 'sanitize';
      final sanitized = await _sanitizeRow(table, object, jwt: jwt);
      logger.trace('sanitize');

      step = 'expand';
      final expanded = await _expandRow(table, sanitized, payload.expand, jwt);
      if (payload.expand.isNotEmpty) {
        logger.trace('expand', extra: {'fields': payload.expand.length});
      }
      logger.trace('done');
      return expanded;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }
}
