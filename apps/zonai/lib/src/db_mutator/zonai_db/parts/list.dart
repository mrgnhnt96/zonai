part of zonai_db;

extension _ListX on ZonaiDb {
  Future<_CrudPaginatedResult> _list(
    String table,
    ListPayload payload, {
    Jwt? userJwt,
  }) async {
    logger.setTraceProps({'op': 'list', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt =
          userJwt ??
          switch (payload) {
            ListWithJwtPayload(:final userJwt) => switch (userJwt) {
              null => null,
              final jwt => await _validateJwt(jwt),
            },
            final ListPayload payload => await _extractJwt(payload),
          };
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireTableAccess(table, .list, jwt);
      logger.trace('table_access');

      step = 'count_query';
      final count = await _count(
        table,
        CountPayload(where: payload.where),
        userJwt: jwt,
        trace: false,
        skipTableAccess: true,
      );
      logger.trace('count_query', extra: {'count': count});

      step = 'sql_build';
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
      logger.trace('sql_build');

      step = 'sql_execute';
      final (error, result) = await _execute((
        operation.query,
        operation.values,
      ));
      logger.trace('sql_execute');
      if (error != null || result == null) {
        _throwDatabaseError(
          error,
          table: table,
          failure: ([cause]) =>
              RecordListFailedException(table: table, cause: cause),
        );
      }

      final objects = result.rows.map((e) => e.toMap()).toList();
      logger.verbose('Found ${objects.length} objects', prefix: _prefix);

      step = 'row_access';
      await _requireRowsAccess(table, .view, objects, jwt);
      logger.trace('row_access', extra: {'rows': objects.length});

      step = 'sanitize';
      final sanitized = await _sanitizeRows(table, objects, jwt: jwt);
      logger.trace('sanitize');

      step = 'expand';
      final expanded = await _expandRows(table, sanitized, payload.expand, jwt);
      if (payload.expand.isNotEmpty) {
        logger.trace('expand', extra: {'fields': payload.expand.length});
      }
      logger.trace('done');

      return Paginated(items: expanded, total: count);
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }
}
