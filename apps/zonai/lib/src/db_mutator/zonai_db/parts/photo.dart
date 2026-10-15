part of zonai_db;

extension _PhotoX on ZonaiDb {
  Future<PhotoView> _getPhoto(String id, {required String? token}) async {
    logger.setTraceProps({'op': 'photo_get'});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await zonaiDB.parseJwt(token);
      logger.trace('jwt_extract');

      final table = photos.$;
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
      final storage = await _photoStorage();
      final stored = await storage.stat(photo.path);
      logger.trace('file_check', extra: {'exists': stored != null});

      if (stored == null) {
        throw const PhotoFileNotFoundException();
      }

      step = 'anonymous_access';
      // A caller with no JWT just passed both rules, so the answer is known.
      final publiclyViewable =
          jwt == null ||
          await _anonymousCanView(table.name, table.mapOut(photo));
      logger.trace('anonymous_access', extra: {'public': publiclyViewable});

      logger.trace('done');
      return PhotoView.stored(
        storage,
        stored,
        publiclyViewable: publiclyViewable,
      );
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Whether a caller with no JWT passes the table and row `canView` rules
  /// for [row].
  ///
  /// Asked so the response can say `private` when the answer is no: a shared
  /// cache serves what it stored to everyone, so a photo stored under
  /// `public` would bypass these rules for every later caller. A rule that
  /// throws without a JWT counts as a no, because this check exists to fail
  /// closed.
  Future<bool> _anonymousCanView(String table, Map<String, dynamic> row) async {
    try {
      final tableRules = await _tableRules(table, .view, null);
      if (!tableRules.canAccess) return false;
      if (tableRules.skipRowChecks) return true;

      final rowRules = await _dispatchRules<RowRulesResponse>(
        RowRulesRequest(
          table: table,
          operation: RowOperation.view.name,
          data: row,
          updates: const [],
          jwt: null,
        ),
      );
      return rowRules?.canPerform == true;
    } on Object catch (e) {
      logger.trace('anonymous_access failed: ${e.runtimeType}');
      return false;
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

    final table = photos.$;
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
    final storage = await _photoStorage();
    if (await storage.exists(relativePath)) {
      throw PhotoFileAlreadyExistsException(path: relativePath);
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

      await storage.write(
        relativePath,
        PhotoStreamUtils.limitedPhotoImageStream(
          image: imageStream,
          maxBytes: photosConfig.maxBytes,
        ),
      );
      logger.trace('file_write');

      await _postCreate(table.name, jwt, object: table.mapOut(insertedRow));
    } catch (e) {
      await storage.delete(relativePath);
      if (insertedRow case final row?) {
        final db = await open();
        await db.delete(from: photos).where(photos.id.equals(row.id));
      }

      await _runExtension(
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
    final table = photos.$;
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

    final storage = await _photoStorage();
    final oldPath = photo.path;
    if (!await storage.exists(oldPath)) {
      throw const PhotoFileNotFoundException();
    }

    final newRelativePath = fs.path.normalize(
      fs.path.join(photo.table, '${photo.id.value}.${imageType.fileExtension}'),
    );
    final extensionChanged = imageType.fileExtension != photo.extension;

    if (extensionChanged && await storage.exists(newRelativePath)) {
      throw PhotoFileAlreadyExistsException(path: newRelativePath);
    }

    final targetPath = extensionChanged ? newRelativePath : oldPath;
    final tempPath = '$targetPath.tmp';

    PhotoEntry? updatedRow;

    try {
      await _runExtension(
        BeforeUpdateExtensionRequest(
          table: table.name,
          objects: [table.mapOut(photo)],
          jwt: jwt,
        ),
      );

      await storage.delete(tempPath);

      await storage.write(
        tempPath,
        PhotoStreamUtils.limitedPhotoImageStream(
          image: imageStream,
          maxBytes: photosConfig.maxBytes,
        ),
      );

      if (extensionChanged) {
        await storage.rename(tempPath, newRelativePath);
        await storage.delete(oldPath);

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
        await storage.delete(oldPath);
        await storage.rename(tempPath, oldPath);
      }

      final afterPhoto = updatedRow ?? photo;

      await _postUpdate(
        table.name,
        jwt,
        before: [table.mapOut(photo)],
        after: [table.mapOut(afterPhoto)],
      );
    } catch (e) {
      await storage.delete(tempPath);
      if (extensionChanged && updatedRow == null) {
        await storage.delete(newRelativePath);
      }

      await _runExtension(
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
    final table = photos.$;
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
      await _runExtension(
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
