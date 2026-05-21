part of zonai_db;

extension _ExpandX on ZonaiDb {
  Future<Map<String, Object?>> _expandRow(
    String collection,
    Map<String, Object?> row,
    List<String> expand,
    Jwt? jwt,
  ) async {
    final rows = await _expandRows(collection, [row], expand, jwt);
    return rows.single;
  }

  Future<List<Map<String, Object?>>> _expandRows(
    String collection,
    List<Map<String, Object?>> rows,
    List<String> expand,
    Jwt? jwt,
  ) async {
    if (expand.isEmpty || rows.isEmpty) {
      return rows;
    }

    final results = <Map<String, Object?>>[];
    for (final row in rows) {
      final result = Map<String, Object?>.from(row);
      final expanded = <String, Object?>{};
      for (final field in expand) {
        final reference = await _getColumnReference(collection, field);
        final fkValue = result[field];
        if (fkValue == null) {
          continue;
        }

        expanded[field] = await _fetchReferencedRecord(
          collection: reference.referencedTable,
          referencedColumn: reference.referencedColumn,
          referencedId: fkValue,
          jwt: jwt,
        );
      }
      result['expanded'] = expanded;
      results.add(result);
    }

    return results;
  }

  Future<_ColumnReference> _getColumnReference(
    String collection,
    String columnName,
  ) async {
    final response = await _operations.send<ColumnReferenceResponse>(
      GetColumnReferenceRequest(
        collection: collection,
        columnName: columnName,
      ),
    );

    final referencedTable = response.referencedTable;
    final referencedColumn = response.referencedColumn;
    if (referencedTable == null || referencedColumn == null) {
      throw StateError(
        'Column "$columnName" on "$collection" cannot be expanded',
      );
    }

    return _ColumnReference(
      columnName: response.columnName,
      referencedTable: referencedTable,
      referencedColumn: referencedColumn,
    );
  }

  Future<Map<String, Object?>> _fetchReferencedRecord({
    required String collection,
    required String referencedColumn,
    required Object referencedId,
    required Jwt? jwt,
  }) async {
    await _requireCollectionAccess(collection, .view, jwt);

    final operation = await _getOperation(
      ReadOperationRequest(
        collection: collection,
        where: Eq(referencedColumn, referencedId),
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to read expanded record');
    }

    if (result.rows.isEmpty) {
      return const {};
    }

    final object = result.rows.first.toMap();
    await _requireRecordAccess(collection, .view, object, jwt);

    return await _sanitizeRow(collection, object);
  }
}

final class _ColumnReference {
  const _ColumnReference({
    required this.columnName,
    required this.referencedTable,
    required this.referencedColumn,
  });

  final String columnName;
  final String referencedTable;
  final String referencedColumn;
}
