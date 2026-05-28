part of zonai_db;

extension _ResolvePhotosX on ZonaiDb {
  Future<List<Map<String, Object?>>> _resolvePhotoFields(
    List<Map<String, Object?>> rows,
    List<String> photoColumns,
  ) async {
    if (rows.isEmpty || photoColumns.isEmpty) {
      return rows;
    }

    final photoIds = <String>{};
    for (final row in rows) {
      for (final column in photoColumns) {
        final value = row[column];
        if (value == null) {
          continue;
        }

        switch (value) {
          case final List<Object?> list:
            for (final id in list) {
              if (id is String) {
                photoIds.add(id);
              }
            }

          case final String id:
            photoIds.add(id);
        }
      }
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
