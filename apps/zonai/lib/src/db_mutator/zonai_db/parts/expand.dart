part of zonai_db;

const _maxExpandDepth = 4;

extension _ExpandX on ZonaiDb {
  Future<Map<String, Object?>> _expandRow(
    String table,
    Map<String, Object?> row,
    List<String> expand,
    Jwt? jwt,
  ) async {
    final rows = await _expandRows(table, [row], expand, jwt);
    return rows.single;
  }

  Future<List<Map<String, Object?>>> _expandRows(
    String table,
    List<Map<String, Object?>> rows,
    List<String> expand,
    Jwt? jwt,
  ) async {
    if (expand.isEmpty || rows.isEmpty) {
      return rows;
    }

    final tree = _ExpandPathTree.fromPaths(expand);
    if (tree.isEmpty) {
      return rows;
    }

    final results = <Map<String, Object?>>[];
    for (final row in rows) {
      results.add(
        await _expandRecord(table, Map<String, Object?>.from(row), tree, jwt),
      );
    }

    return results;
  }

  Future<Map<String, Object?>> _expandRecord(
    String table,
    Map<String, Object?> row,
    _ExpandPathTree tree,
    Jwt? jwt,
  ) async {
    final expanded = <String, Object?>{};

    for (final MapEntry(key: field, value: childTree)
        in tree.children.entries) {
      final fkValue = row[field];
      if (fkValue == null) {
        continue;
      }

      final reference = await _getColumnReference(table, field);
      var related = await _fetchReferencedRecord(
        table: reference.referencedTable,
        referencedColumn: reference.referencedColumn,
        referencedId: fkValue,
        jwt: jwt,
      );

      if (related.isNotEmpty && !childTree.isEmpty) {
        related = await _expandRecord(
          reference.referencedTable,
          related,
          childTree,
          jwt,
        );
      }

      expanded[field] = related;
    }

    final result = Map<String, Object?>.from(row);
    if (expanded.isNotEmpty) {
      result['expanded'] = expanded;
    }
    return result;
  }

  Future<_ColumnReference> _getColumnReference(
    String table,
    String columnName,
  ) async {
    final response = await _operations.send<ColumnReferenceResponse>(
      GetColumnReferenceRequest(table: table, columnName: columnName),
    );

    final referencedTable = response.referencedTable;
    final referencedColumn = response.referencedColumn;
    if (referencedTable == null || referencedColumn == null) {
      throw ColumnNotExpandableException(table: table, columnName: columnName);
    }

    return _ColumnReference(
      columnName: response.columnName,
      referencedTable: referencedTable,
      referencedColumn: referencedColumn,
    );
  }

  Future<Map<String, Object?>> _fetchReferencedRecord({
    required String table,
    required String referencedColumn,
    required Object referencedId,
    required Jwt? jwt,
  }) async {
    await _requireTableAccess(table, .view, jwt);

    final operation = await _getOperation(
      ReadOperationRequest(
        table: table,
        where: Eq(referencedColumn, referencedId),
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw mapDatabaseError(
        error ?? const ExpandedRecordReadFailedException(),
        table: table,
        orElse: (_) => ExpandedRecordReadFailedException(cause: error),
      );
    }

    if (result.rows.isEmpty) {
      logger.trace('fetch_ref', extra: {'found': false, 'ref': table});
      return const {};
    }

    final object = result.rows.first.toMap();
    await _requireRowAccess(table, .view, object, jwt);

    final sanitized = await _sanitizeRow(table, object, jwt: jwt);
    logger.trace('fetch_ref', extra: {'found': true, 'ref': table});
    return sanitized;
  }
}

final class _ExpandPathTree {
  _ExpandPathTree();

  final Map<String, _ExpandPathTree> children = {};

  bool get isEmpty => children.isEmpty;

  static _ExpandPathTree fromPaths(List<String> expand) {
    final tree = _ExpandPathTree();
    for (final path in expand) {
      final segments = path.split('.').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        continue;
      }
      if (segments.length > _maxExpandDepth) {
        throw ColumnNotExpandableException(
          table: segments.first,
          columnName: path,
        );
      }
      tree._addPath(segments);
    }
    return tree;
  }

  void _addPath(List<String> segments) {
    var node = this;
    for (final segment in segments) {
      node = node.children.putIfAbsent(segment, _ExpandPathTree.new);
    }
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
