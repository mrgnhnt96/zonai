part of zonai_db;

extension _PhotoX on ZonaiDb {
  Future<File> _getPhoto(String id, {required String? token}) async {
    final jwt = await zonaiDB.parseJwt(token);

    final table = Table.get(photos);
    if (table == null) {
      throw StateError('Photos table not found');
    }

    await _requireTableAccess(table.name, .view, jwt);

    // drop the extension if provided
    final idOnly = id.split('.').first;
    if (!idOnly.endsWith('ph')) {
      throw StateError('Invalid photo id: $idOnly');
    }
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

    await _requireRowAccess(table.name, .view, table.mapOut(photo), jwt);

    final file = fs.file(fs.path.join(settings.imagesPath, photo.path));

    if (!file.existsSync()) {
      throw StateError('Photo file not found');
    }

    return file;
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
    await _requireRegisteredTable(meta.table);

    final config = await configResolver.resolve();
    final photosConfig = config.photos;

    final (imageType, imageStream) = await PhotoStreamUtils.resolveUploadStream(
      source: image,
      contentType: contentType,
      requiredMimeType: photosConfig.requiredMimeType,
    );

    if (photosConfig.allowedMimeTypes case final allowed?) {
      if (!allowed.contains(imageType)) {
        throw StateError('Content type not allowed: ${imageType.mimeType}');
      }
    }

    final id = Id.generate('ph');
    final relativePath = fs.path.normalize(
      fs.path.join(meta.table, '$id.${imageType.fileExtension}'),
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
      extension: imageType.fileExtension,
      createdAt: .now(),
    );

    await _requireRowAccess(table.name, .create, table.mapOut(entry), jwt);

    PhotoEntry? insertedRow;

    try {
      final db = await open();
      final results = await db.insert(into: photos).values([
        entry,
      ]).returning();

      insertedRow = results.firstOrNull;
      if (insertedRow == null) {
        throw StateError('Photo insert did not return a row');
      }

      await file.parent.create(recursive: true);
      await file.openWrite().addStream(
        PhotoStreamUtils.limitedPhotoImageStream(
          image: imageStream,
          maxBytes: photosConfig.maxBytes,
        ),
      );

      await _postCreate(table.name, jwt, object: table.mapOut(insertedRow));
    } catch (e) {
      if (file.existsSync()) {
        await file.delete();
      }
      if (insertedRow case final row?) {
        final db = await open();
        await db.delete(from: photos).where(photos.id.equals(row.id));
      }

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

    return {'id': insertedRow.id.value};
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

    await _requireRowAccess(table.name, .update, table.mapOut(photo), jwt);

    final config = await configResolver.resolve();
    final photosConfig = config.photos;

    final (detected, imageStream) = await PhotoStreamUtils.detectMimeType(
      image,
    );
    if (detected == null) {
      throw StateError('Could not detect image type from stream');
    }
    final imageType = detected;

    if (photosConfig.allowedMimeTypes case final allowed?) {
      if (!allowed.contains(imageType)) {
        throw StateError('Content type not allowed: ${imageType.mimeType}');
      }
    }

    final oldFile = fs.file(fs.path.join(settings.imagesPath, photo.path));
    if (!oldFile.existsSync()) {
      throw StateError('Photo file not found');
    }

    final newRelativePath = fs.path.normalize(
      fs.path.join(photo.table, '${photo.id.value}.${imageType.fileExtension}'),
    );
    final newFile = fs.file(fs.path.join(settings.imagesPath, newRelativePath));
    final extensionChanged = imageType.fileExtension != photo.extension;

    if (extensionChanged && newFile.existsSync()) {
      throw StateError('Photo file already exists');
    }

    final targetFile = extensionChanged ? newFile : oldFile;
    final tempFile = fs.file('${targetFile.path}.tmp');

    PhotoEntry? updatedRow;

    try {
      await _extensions.send<NoActionExtensionResponse>(
        BeforeUpdateExtensionRequest(
          table: table.name,
          objects: [table.mapOut(photo)],
          jwt: jwt,
        ),
      );

      if (tempFile.existsSync()) {
        await tempFile.delete();
      }

      await tempFile.openWrite().addStream(
        PhotoStreamUtils.limitedPhotoImageStream(
          image: imageStream,
          maxBytes: photosConfig.maxBytes,
        ),
      );

      if (extensionChanged) {
        await tempFile.rename(newFile.path);
        if (oldFile.existsSync()) {
          await oldFile.delete();
        }

        await db
            .update(photos)
            .set(
              photos.path.to(newRelativePath),
              photos.extension.to(imageType.fileExtension),
            )
            .where(photos.id.equals(photo.id));
        updatedRow = PhotoEntry(
          id: photo.id,
          ownerId: photo.ownerId,
          ownerTable: photo.ownerTable,
          table: photo.table,
          path: newRelativePath,
          extension: imageType.fileExtension,
          createdAt: photo.createdAt,
        );
      } else {
        if (oldFile.existsSync()) {
          await oldFile.delete();
        }
        await tempFile.rename(oldFile.path);
      }

      final afterPhoto = updatedRow ?? photo;

      await _postUpdate(
        table.name,
        jwt,
        before: [table.mapOut(photo)],
        after: [table.mapOut(afterPhoto)],
      );
    } catch (e) {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      if (extensionChanged && newFile.existsSync() && updatedRow == null) {
        await newFile.delete();
      }

      await _extensions.send<NoActionExtensionResponse>(
        ErrorExtensionRequest.update(
          table: table.name,
          error: e.toString(),
          jwt: jwt,
        ),
      );

      rethrow;
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

    await _requireRowAccess(table.name, .delete, table.mapOut(photo), jwt);

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
