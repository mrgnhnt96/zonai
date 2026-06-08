part of zonai_db;

extension _ResolvePhotosX on ZonaiDb {
  Future<List<String>> _photoColumnsFor(String table) async {
    final response = await _operations.send<SanitizeOperationResponse>(
      SanitizeOperationRequest(table: table, objects: const [{}]),
    );

    return response.photoColumns;
  }

  /// checks whether the table has photo columns
  Future<void> _requireRegisteredTable(String table) async {
    await _photoColumnsFor(table);
  }

  Future<void> _requirePhotoReferences(
    String table,
    Map<String, Object?> data,
  ) async {
    final photoColumns = await _photoColumnsFor(table);
    if (photoColumns.isEmpty) {
      return;
    }

    final photoIds = _collectPhotoIds(data, photoColumns);
    await _verifyPhotoIds(table, photoIds);
  }

  Future<void> _requirePhotoReferencesFromUpdates(
    String table,
    List<Update> updates,
  ) async {
    final photoColumns = await _photoColumnsFor(table);
    if (photoColumns.isEmpty) {
      return;
    }

    final photoColumnSet = photoColumns.toSet();
    final photoIds = <String>{};

    for (final update in updates) {
      switch (update) {
        case ObjectUpdate(:final object):
          photoIds.addAll(_collectPhotoIds(object, photoColumns));
        case ColumnUpdate(:final column, :final value)
            when photoColumnSet.contains(column):
          switch (value) {
            case Literal(:final value):
              photoIds.addAll(_collectPhotoIds({column: value}, [column]));
            case Add(:final value):
              photoIds.addAll(_collectPhotoIds({column: value}, [column]));
            case AddAll(:final values):
              photoIds.addAll(_collectPhotoIds({column: values}, [column]));
            case Increment() || Decrement() || Remove() || RemoveAll():
          }
        case ColumnUpdate():
          break;
      }
    }

    await _verifyPhotoIds(table, photoIds);
  }

  Future<void> _verifyPhotoIds(String table, Set<String> photoIds) async {
    if (photoIds.isEmpty) {
      return;
    }

    final db = await open();

    for (final id in photoIds) {
      final rows = await db
          .select()
          .from(photos)
          .where(photos.id.equals(PhotoId(id)))
          .limit(1);

      if (rows.isEmpty) {
        throw PhotoNotFoundException(id: id);
      }

      final row = rows.first;
      if (row.table != table) {
        throw PhotoNotFoundException(id: id);
      }
    }
  }

  Future<List<Map<String, Object?>>> _resolvePhotoFields(
    List<Map<String, Object?>> rows,
    List<String> photoColumns,
  ) async {
    if (rows.isEmpty || photoColumns.isEmpty) {
      return rows;
    }

    final photoIds = <String>{};
    for (final row in rows) {
      photoIds.addAll(_collectPhotoIds(row, photoColumns));
    }

    if (photoIds.isEmpty) {
      return rows;
    }

    final extensions = await _photoExtensionsById(photoIds);
    final baseUrl = (await configResolver.resolve()).baseUrl;

    return [
      for (final row in rows)
        _resolvePhotoRow(
          row,
          photoColumns: photoColumns,
          baseUrl: baseUrl,
          extensions: extensions,
        ),
    ];
  }

  Map<String, Object?> _resolvePhotoRow(
    Map<String, Object?> row, {
    required List<String> photoColumns,
    required String baseUrl,
    required Map<String, String?> extensions,
  }) {
    final resolved = Map<String, Object?>.from(row);

    for (final column in photoColumns) {
      final value = resolved[column];
      if (value == null) {
        continue;
      }

      resolved[column] = switch (value) {
        final List<Object?> list => [
          for (final id in list)
            if (id is String)
              _buildPhotoUrl(
                baseUrl: baseUrl,
                id: id,
                extension: extensions[id],
              )
            else
              id,
        ],
        final String id => _buildPhotoUrl(
          baseUrl: baseUrl,
          id: id,
          extension: extensions[id],
        ),
        _ => value,
      };
    }

    return resolved;
  }

  Future<Map<String, String?>> _photoExtensionsById(Set<String> ids) async {
    if (ids.isEmpty) {
      return const {};
    }

    final db = await open();
    final extensions = <String, String?>{};

    for (final id in ids) {
      final rows = await db
          .select()
          .from(photos)
          .where(photos.id.equals(PhotoId(id)))
          .limit(1);

      if (rows case [final photo]) {
        extensions[id] = photo.extension;
      }
    }

    return extensions;
  }
}

Set<String> _collectPhotoIds(
  Map<String, Object?> data,
  List<String> photoColumns,
) {
  final photoIds = <String>{};

  for (final column in photoColumns) {
    final value = data[column];
    if (value == null) {
      continue;
    }

    switch (value) {
      case final List<Object?> list:
        for (final id in list) {
          if (id is String && id.isNotEmpty) {
            photoIds.add(id);
          }
        }

      case final String id when id.isNotEmpty:
        photoIds.add(id);

      case _:
    }
  }

  return photoIds;
}

String _buildPhotoUrl({
  required String baseUrl,
  required String id,
  String? extension,
}) {
  final normalizedBase = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  if (extension case final ext? when ext.isNotEmpty) {
    return '$normalizedBase/img/$id.$ext';
  }

  return '$normalizedBase/img/$id';
}
