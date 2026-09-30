part of zonai_db;

/// How many rows the filtered count reads per rules round trip.
const _countPageSize = 500;

extension _CountX on ZonaiDb {
  Future<int> _count(
    String table,
    CountPayload payload, {
    Jwt? userJwt,
    bool trace = true,
    TableRulesResponse? access,
  }) async {
    if (trace) {
      logger.setTraceProps({'op': 'count', 'table': table});
      logger.trace('start');
    }

    final jwt = userJwt ?? await _extractJwt(payload, allowApiToken: true);
    final verdict = access ?? await _requireTableAccess(table, .list, jwt);

    final count = await _visibleCount(table, payload.where, jwt, verdict);
    if (trace) logger.trace('done', extra: {'count': count});
    return count;
  }

  /// The number of rows matching [where] that [jwt] may view.
  ///
  /// A count used to check only the table rule and then run `COUNT(*)` over
  /// [where] -- so on a table whose rows are private to their owner, any
  /// caller the table rule admitted learned how many rows every other owner
  /// had, under any filter they chose (`/db/count`, the `total` of
  /// `/db/list`, and the count stream).
  ///
  /// A bare `COUNT` is only honest when every matching row is one the caller
  /// may see. Two things establish that:
  ///
  ///  - the row rules opted out of per-row checks
  ///    ([TableRulesResponse.skipRowChecks]), or
  ///  - they declared a scope ([TableRulesResponse.scope]), which is ANDed in:
  ///    the rule author's statement of what this caller may see. A scope that
  ///    admits rows `canView` refuses is inconsistent, and is documented as
  ///    such on `BaseRowRules.viewScope`.
  ///
  /// Otherwise the rows are read and put through `canView`, a page at a time
  /// ([_filteredCount]). That is slower -- one rules round trip per
  /// [_countPageSize] rows -- and it is the price of a count that says only
  /// what the caller may know. Declaring a scope is how a table gets the fast
  /// path back.
  Future<int> _visibleCount(
    String table,
    Where? where,
    Jwt? jwt,
    TableRulesResponse access,
  ) async {
    final scoped = _scoped(where, access.scope);
    if (access.skipRowChecks || access.scope != null) {
      return _sqlCount(table, scoped, jwt);
    }
    return _filteredCount(table, scoped, jwt);
  }

  Future<int> _sqlCount(String table, Where? where, Jwt? jwt) async {
    final operation = await _getOperation(
      CountOperationRequest(table: table, where: where, jwt: jwt),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      _throwDatabaseError(
        error,
        table: table,
        failure: ([cause]) =>
            RecordCountFailedException(table: table, cause: cause),
      );
    }

    return _countFromResult(result);
  }

  /// Counts the rows matching [where] that pass `canView` for [jwt].
  Future<int> _filteredCount(String table, Where? where, Jwt? jwt) async {
    var total = 0;
    var offset = 0;
    while (true) {
      final operation = await _getOperation(
        ListOperationRequest(
          table: table,
          where: where,
          limit: _countPageSize,
          offset: offset,
          jwt: jwt,
        ),
      );

      final (error, result) = await _execute((
        operation.query,
        operation.values,
      ));
      if (error != null || result == null) {
        _throwDatabaseError(
          error,
          table: table,
          failure: ([cause]) =>
              RecordCountFailedException(table: table, cause: cause),
        );
      }

      final rows = result.rows.map((e) => e.toMap()).toList();
      if (rows.isEmpty) break;

      total += (await _filterRowsAccess(table, .view, rows, jwt)).length;
      if (rows.length < _countPageSize) break;
      offset += rows.length;
    }
    return total;
  }

  Stream<int> _streamCount(String table, CountPayload payload) async* {
    final jwt = await _extractJwt(payload, allowApiToken: true);
    final access = await _requireTableAccess(table, .list, jwt);
    final scoped = _scoped(payload.where, access.scope);

    // What re-runs the count. For a bare COUNT it is the COUNT itself. For a
    // filtered one it has to be the matching ROWS: an edit that moves a row
    // out of this caller's view (reassigning its owner) changes which rows
    // pass `canView` without changing how many rows match the filter, so a
    // COUNT would never re-emit for it.
    final trigger = await _getOperation(
      access.skipRowChecks || access.scope != null
          ? CountOperationRequest(table: table, where: scoped, jwt: jwt)
          : ListOperationRequest(
              table: table,
              where: scoped,
              limit: null,
              offset: null,
              jwt: jwt,
            ),
    );

    // only yield counts when the count changes
    yield* _stream(trigger.query, trigger.values)
        .asyncMap((_) => _visibleCount(table, payload.where, jwt, access))
        .distinct();
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
