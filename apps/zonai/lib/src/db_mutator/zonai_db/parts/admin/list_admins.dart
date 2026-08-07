part of zonai_db;

extension _ListAdminsX on ZonaiDb {
  Future<List<Map<String, Object?>>> _listAdmins() async {
    final table = await _adminCollectionFor(.password);

    final operation = await _dispatchOperation<PerformOperationResponse>(
      ListOperationRequest(
        table: table,
        where: null,
        limit: null,
        offset: null,
        jwt: null,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to list admin accounts');
    }

    final rows = result.rows.map((e) => e.toMap()).toList();
    return _sanitizeRows(table, rows);
  }
}
