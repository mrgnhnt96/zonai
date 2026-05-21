part of zonai_db;

const _maxExpandDepth = 4;

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

    final tree = _ExpandPathTree.fromPaths(expand);
    if (tree.isEmpty) {
      return rows;
    }

    final results = <Map<String, Object?>>[];
    for (final row in rows) {
      results.add(
        await _expandRecord(
          collection,
          Map<String, Object?>.from(row),
          tree,
          jwt,
        ),
      );
    }

    return results;
  }

  Future<Map<String, Object?>> _expandRecord(
    String collection,
    Map<String, Object?> record,
    _ExpandPathTree tree,
    Jwt? jwt,
  ) async {
    final expanded = <String, Object?>{};

    for (final MapEntry(key: field, value: childTree)
        in tree.children.entries) {
      final fkValue = record[field];
      if (fkValue == null) {
        continue;
      }

      final reference = await _getColumnReference(collection, field);
      var related = await _fetchReferencedRecord(
        collection: reference.referencedTable,
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

    final result = Map<String, Object?>.from(record);
    if (expanded.isNotEmpty) {
      result['expanded'] = expanded;
    }
    return result;
  }

  Future<_ColumnReference> _getColumnReference(
    String collection,
    String columnName,
  ) async {
    final response = await _operations.send<ColumnReferenceResponse>(
      GetColumnReferenceRequest(collection: collection, columnName: columnName),
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
        throw StateError(
          'Expand path "$path" exceeds maximum depth of $_maxExpandDepth',
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
