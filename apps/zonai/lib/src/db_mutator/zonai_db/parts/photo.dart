part of zonai_db;

extension _PhotoX on ZonaiDb {
  Future<File> _getPhoto(String id, {required String? token}) async {
    logger.setTraceProps({'op': 'photo_get'});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await zonaiDB.parseJwt(token);
      logger.trace('jwt_extract');

      final table = Table.get(photos);
      if (table == null) {
        throw const PhotosTableNotFoundException();
      }

      step = 'table_access';
      await _requireTableAccess(table.name, .view, jwt);
      logger.trace('table_access');

      // drop the extension if provided
      final idOnly = id.split('.').first;
      if (!idOnly.endsWith('ph')) {
        throw InvalidPhotoIdException(id: idOnly);
      }

      step = 'db_lookup';
      final db = await open();
      final rows = await db
          .select()
          .from(photos)
          .where(photos.id.equals(PhotoId(idOnly)))
          .limit(1);
      logger.trace('db_lookup', extra: {'found': rows.isNotEmpty});

      if (rows.isEmpty) {
        throw const PhotoNotFoundException();
      }

      final photo = rows.first;

      step = 'row_access';
      await _requireRowAccess(table.name, .view, table.mapOut(photo), jwt);
      logger.trace('row_access');

      step = 'file_check';
      final file = fs.file(fs.path.join(settings.imagesPath, photo.path));
      logger.trace('file_check', extra: {'exists': file.existsSync()});

      if (!file.existsSync()) {
        throw const PhotoFileNotFoundException();
      }

      logger.trace('done');
      return file;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<Map<String, Object?>> _createPhoto({
    required String? token,
    required PhotoCreateMeta meta,
    required String? contentType,
    required Stream<List<int>> image,
  }) async {
    logger.setTraceProps({'op': 'photo_create'});
    logger.trace('start');

    final jwt = await _extractJwt(JwtPayload(jwt: token));
    logger.trace('jwt_extract');

    final table = Table.get(photos);
    if (table == null) {
      throw const PhotosTableNotFoundException();
    }

    await _requireTableAccess(table.name, .create, jwt);
    logger.trace('table_access');

    await _requireRegisteredTable(meta.table);

    final config = await configResolver.resolve();
    final photosConfig = config.photos;

    final (imageType, imageStream) = await PhotoStreamUtils.resolveUploadStream(
      source: image,
      contentType: contentType,
      requiredMimeType: photosConfig.requiredMimeType,
    );
    logger.trace('stream_resolve', extra: {'type': imageType.mimeType});

    if (photosConfig.allowedMimeTypes case final allowed?) {
      if (!allowed.contains(imageType)) {
        throw PhotoContentTypeNotAllowedException(mimeType: imageType.mimeType);
      }
    }

    final id = Id.generate('ph');
    final relativePath = fs.path.normalize(
      fs.path.join(meta.table, '$id.${imageType.fileExtension}'),
    );
    final file = fs.file(fs.path.join(settings.imagesPath, relativePath));
    if (fs.path.isWithin(settings.imagesPath, relativePath)) {
      throw InvalidPhotoPathException(path: relativePath);
    }
    if (file.existsSync()) {
      throw PhotoFileAlreadyExistsException(path: file.path);
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
    logger.trace('row_access');

    PhotoEntry? insertedRow;

    try {
      final db = await open();
      final results = await db.insert(into: photos).values([entry]).returning();
      logger.trace('db_insert');

      insertedRow = results.firstOrNull;
      if (insertedRow == null) {
        throw const PhotoInsertFailedException();
      }

      await file.parent.create(recursive: true);
      await file.openWrite().addStream(
        PhotoStreamUtils.limitedPhotoImageStream(
          image: imageStream,
          maxBytes: photosConfig.maxBytes,
        ),
      );
      logger.trace('file_write');

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
    logger.trace('done');

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
      throw const PhotosTableNotFoundException();
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
      throw const PhotoNotFoundException();
    }

    final photo = rows.first;

    await _requireRowAccess(table.name, .update, table.mapOut(photo), jwt);

    final config = await configResolver.resolve();
    final photosConfig = config.photos;

    final (detected, imageStream) = await PhotoStreamUtils.detectMimeType(
      image,
    );
    if (detected == null) {
      throw const PhotoImageTypeUndetectableException();
    }
    final imageType = detected;

    if (photosConfig.allowedMimeTypes case final allowed?) {
      if (!allowed.contains(imageType)) {
        throw PhotoContentTypeNotAllowedException(mimeType: imageType.mimeType);
      }
    }

    final oldFile = fs.file(fs.path.join(settings.imagesPath, photo.path));
    if (!oldFile.existsSync()) {
      throw const PhotoFileNotFoundException();
    }

    final newRelativePath = fs.path.normalize(
      fs.path.join(photo.table, '${photo.id.value}.${imageType.fileExtension}'),
    );
    final newFile = fs.file(fs.path.join(settings.imagesPath, newRelativePath));
    final extensionChanged = imageType.fileExtension != photo.extension;

    if (extensionChanged && newFile.existsSync()) {
      throw PhotoFileAlreadyExistsException(path: newFile.path);
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
      throw const PhotosTableNotFoundException();
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
      throw const PhotoNotFoundException();
    }

    final photo = rows.first;

    await _requireRowAccess(table.name, .delete, table.mapOut(photo), jwt);

    try {
      await _deletePhotoEntry(photo, jwt: jwt);
    } catch (e, stack) {
      logger.error('$e', 'Failed to delete photo', stack);
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
