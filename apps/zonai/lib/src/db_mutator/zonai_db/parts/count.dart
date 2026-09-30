part of zonai_db;

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
    if (count == null) throw CountRequiresViewScopeException(table: table);
    if (trace) logger.trace('done', extra: {'count': count});
    return count;
  }

  /// The number of rows matching [where] that [jwt] may view, or `null` when
  /// it cannot be had in one statement.
  ///
  /// A count used to check only the table rule and then run `COUNT(*)` over
  /// [where] -- so on a table whose rows are private to their owner, any
  /// caller the table rule admitted learned how many rows every other owner
  /// had, under any filter they chose (`/db/count`, the `total` of
  /// `/db/list`, and the count stream).
  ///
  /// A plain `COUNT` is honest when every matching row is one the caller may
  /// see, which one of these establishes:
  ///
  ///  - the row rules declared a scope ([TableRulesResponse.scope]), ANDed in:
  ///    the rule author's statement of what this caller may see;
  ///  - the row rules opted out of per-row checks
  ///    ([TableRulesResponse.skipRowChecks]);
  ///  - the caller is an admin.
  ///
  /// Otherwise there is no cheap honest answer. Counting by reading every
  /// matching row through `canView` was tried first and refused in review:
  /// it made every `/db/list` total, `/db/count` and count-stream event
  /// O(table) for any caller, with rate limits only per IP. So `null`, and
  /// the caller decides: a count refuses (naming `viewScope`), a list omits
  /// its total.
  Future<int?> _visibleCount(
    String table,
    Where? where,
    Jwt? jwt,
    TableRulesResponse access,
  ) async {
    if (!_countIsCheap(jwt, access)) return null;
    return _sqlCount(table, _scoped(where, access.scope), jwt);
  }

  bool _countIsCheap(Jwt? jwt, TableRulesResponse access) =>
      access.scope != null ||
      access.skipRowChecks ||
      (jwt?.admin.isAdmin ?? false);

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

  Stream<int> _streamCount(String table, CountPayload payload) async* {
    final jwt = await _extractJwt(payload, allowApiToken: true);
    final access = await _requireTableAccess(table, .list, jwt);
    if (!_countIsCheap(jwt, access)) {
      throw CountRequiresViewScopeException(table: table);
    }

    final operation = await _getOperation(
      CountOperationRequest(
        table: table,
        where: _scoped(payload.where, access.scope),
        jwt: jwt,
      ),
    );

    // only yield counts when the count changes
    yield* _stream(
      operation.query,
      operation.values,
    ).map(_countFromResult).distinct();
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
