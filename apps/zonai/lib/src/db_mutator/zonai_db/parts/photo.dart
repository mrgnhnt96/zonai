part of zonai_db;

extension _PhotoX on ZonaiDb {
  Stream<List<int>> _getPhoto(String id, {required String? token}) async* {
    final jwt = await zonaiDB.parseJwt(token);

    final table = Table.get(photos);
    if (table == null) {
      throw StateError('Photos table not found');
    }

    await _requireTableAccess(table.name, .view, jwt);

    // drop the extension if provided
    final idOnly = id.split('.').first;
    final db = await open();
    final rows = await db
        .select()
        .from(photos)
        .where(photos.id.equals(PhotoId(idOnly)))
        .limit(1);

    if (rows.isEmpty) {
      throw StateError('Photo not found');
    }

    final photo = rows.first;

    await _requireRecordAccess(table.name, .view, table.mapOut(photo), jwt);

    final file = fs.file(fs.path.join(settings.imagesPath, photo.path));

    if (!file.existsSync()) {
      throw StateError('Photo file not found');
    }

    yield* file.openRead();
  }

  Future<Map<String, Object?>> _createPhoto({
    required String? token,
    required PhotoCreateMeta meta,
    required String? contentType,
    required Stream<List<int>> image,
  }) async {
    final jwt = await _extractJwt(JwtPayload(jwt: token));
    final table = Table.get(photos);
    if (table == null) {
      throw StateError('Photos table not found');
    }
    await _requireTableAccess(table.name, .create, jwt);

    final rawExtension = contentType?.split(';').first.trim().toLowerCase();

    final extension = switch (rawExtension) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'bin',
    };

    final id = Id.generate('ph');
    final relativePath = fs.path.normalize(
      fs.path.join(meta.table, '$id.$extension'),
    );
    final file = fs.file(fs.path.join(settings.imagesPath, relativePath));
    if (fs.path.isWithin(settings.imagesPath, relativePath)) {
      throw StateError('Invalid photo path: $relativePath');
    }
    if (file.existsSync()) {
      throw StateError('Photo file already exists');
    }

    final entry = PhotoEntry(
      id: PhotoId(id),
      ownerId: jwt?.userId ?? UnknownId(''),
      ownerTable: jwt?.table ?? '',
      table: meta.table,
      path: relativePath,
      extension: extension,
      createdAt: .now(),
    );

    await _requireRecordAccess(table.name, .create, table.mapOut(entry), jwt);

    PhotoEntry row;

    try {
      final db = await open();
      final [result] = await db.insert(into: photos).values([
        entry,
      ]).returning();

      await file.parent.create(recursive: true);
      await file.openWrite().addStream(image);

      row = result;
      await _postCreate(table.name, jwt, object: table.mapOut(row));
    } catch (e, stack) {
      logger.error('$e', 'Failed to create photo', stack);
      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.create(
          table: table.name,
          error: e.toString(),
          jwt: jwt,
        ),
      );

      rethrow;
    }

    await _executeEffects();

    return {'id': row.id.value};
  }

  Future<void> _updatePhoto({
    required String? token,
    required String id,
    required Stream<List<int>> image,
  }) async {
    final jwt = await _extractJwt(JwtPayload(jwt: token));
    final table = Table.get(photos);
    if (table == null) {
      throw StateError('Photos table not found');
    }
    await _requireTableAccess(table.name, .update, jwt);

    final db = await open();
    final rows = await db
        .select()
        .from(photos)
        .where(photos.id.equals(PhotoId(id)))
        .limit(1);

    if (rows.isEmpty) {
      throw StateError('Photo not found');
    }

    final photo = rows.first;

    await _requireRecordAccess(table.name, .update, table.mapOut(photo), jwt);
    final file = fs.file(fs.path.join(settings.imagesPath, photo.path));
    if (!file.existsSync()) {
      throw StateError('Photo file not found');
    }

    try {
      await _extensions.send<NoActionExtensionResponse>(
        BeforeUpdateExtensionRequest(
          table: table.name,
          objects: [table.mapOut(photo)],
          jwt: jwt,
        ),
      );

      await file.openWrite().addStream(image);

      await _postUpdate(
        table.name,
        jwt,
        before: [table.mapOut(photo)],
        after: [table.mapOut(photo)],
      );
    } catch (e, stack) {
      logger.error('$e', 'Failed to update photo', stack);
      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.update(
          table: table.name,
          error: e.toString(),
          jwt: jwt,
        ),
      );
    }

    await _executeEffects();
  }

  Future<void> _deletePhoto({
    required String? token,
    required String id,
  }) async {
    final jwt = await _extractJwt(JwtPayload(jwt: token));
    final table = Table.get(photos);
    if (table == null) {
      throw StateError('Photos table not found');
    }
    await _requireTableAccess(table.name, .delete, jwt);

    final db = await open();
    final rows = await db
        .select()
        .from(photos)
        .where(photos.id.equals(PhotoId(id)))
        .limit(1);

    if (rows.isEmpty) {
      throw StateError('Photo not found');
    }

    final photo = rows.first;

    await _requireRecordAccess(table.name, .delete, table.mapOut(photo), jwt);

    try {
      await _extensions.send<NoActionExtensionResponse>(
        DeleteExtensionRequest.before(
          table: table.name,
          objects: [table.mapOut(photo)],
          jwt: jwt,
        ),
      );

      final file = fs.file(fs.path.join(settings.imagesPath, photo.path));
      if (file.existsSync()) {
        await file.delete();
      }

      await _postDelete(table.name, jwt, objects: [table.mapOut(photo)]);
    } catch (e, stack) {
      logger.error('$e', 'Failed to update photo', stack);
      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.delete(
          table: table.name,
          error: e.toString(),
          jwt: jwt,
        ),
      );
    }

    await _executeEffects();
  }
}
