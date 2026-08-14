part of zonai_db;

extension _CleanupPhotosX on ZonaiDb {
  /// Deletes `_photos` rows (and their files) that are not referenced by any
  /// `photo` / `photos` column in user collections.
  Future<int> _cleanupUnreferencedPhotos() async {
    final db = await open();
    final shapes = await schemaShapes();
    final referencedIds = await _collectReferencedPhotoIds(shapes);

    const gracePeriod = Duration(hours: 1);
    final cutoff = DateTime.now().subtract(gracePeriod);
    final rows = await db.select().from(photos);

    var deleted = 0;
    for (final photo in rows) {
      if (photo.createdAt.isAfter(cutoff)) {
        continue;
      }

      if (referencedIds.contains(photo.id.value)) {
        continue;
      }

      await _deletePhotoEntry(photo, jwt: CronJwt());
      deleted++;
    }

    return deleted;
  }

  Future<Set<String>> _collectReferencedPhotoIds(
    Map<String, TableSchemaShape> shapes,
  ) async {
    final referencedIds = <String>{};

    for (final shape in shapes.values) {
      if (InternalDbArtifacts.tableNames.contains(shape.table)) {
        continue;
      }

      final photoColumns = [
        for (final column in shape.columns)
          switch (column.kind) {
            ColumnShapeKind.photo => (name: column.name, isArray: false),
            ColumnShapeKind.photos => (name: column.name, isArray: true),
            _ => null,
          },
      ].nonNulls;

      if (photoColumns.isEmpty) {
        continue;
      }

      final operation = await _getOperation(
        ListOperationRequest(
          table: shape.table,
          where: const And([]),
          limit: null,
          offset: null,
          jwt: CronJwt(),
        ),
      );

      final (_, result) = await _execute((operation.query, operation.values));
      if (result == null) {
        continue;
      }

      for (final row in result.rows) {
        final map = row.toMap();
        for (final column in photoColumns) {
          referencedIds.addAll(
            _photoIdsFromColumnValue(map[column.name], isArray: column.isArray),
          );
        }
      }
    }

    return referencedIds;
  }

  Future<void> _deletePhotoFile(String relativePath) async {
    final file = fs.file(fs.path.join(settings.imagesPath, relativePath));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _deletePhotoEntry(PhotoEntry photo, {required Jwt? jwt}) async {
    final table = photos.$;
    final object = table.mapOut(photo);

    await _runExtension(
      DeleteExtensionRequest.before(
        table: table.name,
        objects: [object],
        jwt: jwt,
      ),
    );

    await _deletePhotoFile(photo.path);

    final db = await open();
    await db.delete(from: photos).where(photos.id.equals(photo.id));

    await _postDelete(table.name, jwt, objects: [object]);
  }
}

Set<String> _photoIdsFromColumnValue(Object? value, {required bool isArray}) {
  if (value == null) {
    return const {};
  }

  if (isArray) {
    return switch (value) {
      final String json when json.isNotEmpty => _photoIdsFromJsonArray(json),
      final List<Object?> list => {
        for (final id in list)
          if (id is String && id.isNotEmpty) id,
      },
      _ => const {},
    };
  }

  return switch (value) {
    final String id when id.isNotEmpty => {id},
    _ => const {},
  };
}

Set<String> _photoIdsFromJsonArray(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      return const {};
    }

    return {
      for (final id in decoded)
        if (id is String && id.isNotEmpty) id,
    };
  } on FormatException {
    return const {};
  }
}
