part of zonai_db;

/// Rows read per page by either scan below.
///
/// Bounds peak memory for the row set, not for the referenced-id set — see
/// [_CleanupPhotosX._collectReferencedPhotoIds].
const _photoScanPageSize = 500;

extension _CleanupPhotosX on ZonaiDb {
  /// Deletes `_photos` rows (and their files) that are not referenced by any
  /// `photo` / `photos` column in user collections.
  ///
  /// Both scans here are **paged**. The previous version read every `_photos`
  /// row and every row of every photo-bearing collection into memory first,
  /// which is the shape that made `_cleanup_logs` an OOM before `df76021`.
  ///
  /// The per-row delete is NOT a candidate for the same treatment: deleting a
  /// `_photos` row deletes a file, which is why `_photos` is excluded from
  /// `mutate.purge` (see `parts/purge.dart`). A bulk `DELETE ... WHERE` here
  /// would orphan every file it removed a row for, invisibly — the row count
  /// would look correct. The bug was in how candidates are *found*, never in
  /// how each one is *deleted*.
  Future<int> _cleanupUnreferencedPhotos() async {
    final shapes = await schemaShapes();
    final referencedIds = await _collectReferencedPhotoIds(shapes);

    const gracePeriod = Duration(hours: 1);
    final cutoff = DateTime.now().subtract(gracePeriod);

    var deleted = 0;
    String? cursor;

    // Keyset pagination on the primary key, not OFFSET: OFFSET degrades over
    // the scan and can skip or repeat rows when the table is written during
    // it. `id` is the primary key, so ordering by it is total and stable.
    //
    // The cursor is required rather than incidental: a referenced photo is
    // *skipped*, not deleted, so it is still there on the next page. Without a
    // cursor the same page would be re-read forever.
    while (true) {
      final page = await _photoPage(cutoff: cutoff, after: cursor);
      if (page.isEmpty) break;

      for (final row in page) {
        final id = row[photos.id.name] as String?;
        if (id == null) continue;
        cursor = id;

        if (referencedIds.contains(id)) {
          continue;
        }

        await _deletePhotoRow(row, jwt: CronJwt());
        deleted++;
      }

      if (page.length < _photoScanPageSize) break;
    }

    return deleted;
  }

  /// One page of `_photos` rows older than [cutoff], ordered by `id`, starting
  /// after [after].
  ///
  /// The grace period is applied in SQL. It used to be applied in Dart after
  /// the whole table had been read, so rows the query could have excluded were
  /// loaded in order to be thrown away.
  /// Built as SQL here rather than through the operations worker, because
  /// `_photos` is an internal table whose schema Zonai owns statically. Routing
  /// it through `_getOperation` would add a worker round-trip per page and make
  /// this cron untestable without a compiled project — `_collectReferencedPhotoIds`
  /// needs the worker because user collections are only known at runtime, but
  /// this scan does not.
  Future<List<Map<String, Object?>>> _photoPage({
    required DateTime cutoff,
    required String? after,
  }) async {
    final table = photos.$.name;
    final idColumn = photos.id.name;

    // `created_at` is stored as epoch milliseconds (CreatedAtTransformer), so
    // the cutoff has to be compared in the same unit rather than as text.
    final values = <Object?>[cutoff.millisecondsSinceEpoch];
    final buffer = StringBuffer()
      ..write('SELECT * FROM "$table" WHERE "${photos.createdAt.name}" < ?');

    if (after != null) {
      buffer.write(' AND "$idColumn" > ?');
      values.add(after);
    }

    buffer.write(' ORDER BY "$idColumn" ASC LIMIT $_photoScanPageSize');

    final (error, result) = await _execute((buffer.toString(), values));
    if (error != null || result == null) {
      return const [];
    }

    return [for (final row in result.rows) row.toMap()];
  }

  /// Every photo id referenced by a `photo`/`photos` column in any user
  /// collection.
  ///
  /// **This set is the one thing here that is still unbounded, and that is a
  /// recorded limit rather than an oversight.** The algorithm has to know what
  /// is referenced before it can say what is not, so the set grows with the
  /// number of *referenced photos* — no longer with the number of rows, which
  /// is what the paging below fixes. Removing it entirely means an anti-join in
  /// SQL across a set of tables only known at runtime; that is a different
  /// design and was judged not worth it while the set holds ids, not rows.
  ///
  /// What paging does fix: this used to select **all rows and all columns** of
  /// every photo-bearing collection, then read one or two columns back out of
  /// each row. A collection with a photo column and fifty others loaded all
  /// fifty-one.
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

      final idColumn = _primaryKeyColumnName(shape);
      if (idColumn == null) {
        // Nothing stable to page by. Reading it all is the old behaviour and
        // is still correct — just unbounded — so say why rather than skipping
        // the table and silently under-collecting, which would delete photos
        // that ARE referenced.
        logger.warn(
          'Photo cleanup is scanning "${shape.table}" unpaged: no primary key '
          'to order by. Referenced photos are still collected correctly, but '
          'peak memory grows with the table.',
        );
      }

      String? cursor;
      while (true) {
        final operation = await _getOperation(
          ListOperationRequest(
            table: shape.table,
            where: And([
              if (idColumn != null && cursor != null) Gt(idColumn, cursor),
            ]),
            orderBy: idColumn == null ? null : [OrderByTerm(column: idColumn)],
            limit: idColumn == null ? null : _photoScanPageSize,
            offset: null,
            jwt: CronJwt(),
          ),
        );

        final (_, result) = await _execute((operation.query, operation.values));
        if (result == null) {
          break;
        }

        for (final row in result.rows) {
          final map = row.toMap();
          if (idColumn != null) {
            cursor = map[idColumn]?.toString();
          }
          for (final column in photoColumns) {
            referencedIds.addAll(
              _photoIdsFromColumnValue(
                map[column.name],
                isArray: column.isArray,
              ),
            );
          }
        }

        if (idColumn == null || result.rows.length < _photoScanPageSize) {
          break;
        }
      }
    }

    return referencedIds;
  }

  /// The name of [shape]'s primary key column, or null if it has none.
  String? _primaryKeyColumnName(TableSchemaShape shape) {
    for (final column in shape.columns) {
      if (column.isPrimaryKey) return column.name;
    }
    return null;
  }

  Future<void> _deletePhotoFile(String relativePath) async {
    final file = fs.file(fs.path.join(settings.imagesPath, relativePath));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _deletePhotoEntry(PhotoEntry photo, {required Jwt? jwt}) =>
      _deletePhotoRow(photos.$.mapOut(photo), jwt: jwt);

  /// Deletes one `_photos` row and its file.
  ///
  /// Takes the row as a map rather than a [PhotoEntry] because the paged scan
  /// in [_cleanupUnreferencedPhotos] reads rows through the operations layer,
  /// which yields maps — and reconstructing a [PhotoEntry] from one would have
  /// to go through `safeCreate`, which stamps `createdAt` with *now* on the way
  /// through. That is correct for a create and wrong for a row being read.
  ///
  /// **This stays per-row on purpose.** Each iteration deletes a file as well
  /// as a row, which is why `_photos` is excluded from `mutate.purge` (see
  /// `parts/purge.dart`). Converting this to a bulk `DELETE ... WHERE` would
  /// orphan every file it removed a row for, and the row count would still
  /// look right — a silent, permanent disk leak.
  Future<void> _deletePhotoRow(
    Map<String, Object?> object, {
    required Jwt? jwt,
  }) async {
    final table = photos.$;
    final id = object[photos.id.name] as String?;
    if (id == null) return;

    await _runExtension(
      DeleteExtensionRequest.before(
        table: table.name,
        objects: [object],
        jwt: jwt,
      ),
    );

    if (object[photos.path.name] case final String path) {
      await _deletePhotoFile(path);
    }

    final db = await open();
    await db.delete(from: photos).where(photos.id.equals(PhotoId(id)));

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
