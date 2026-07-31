part of zonai_db;

extension _CreateX on ZonaiDb {
  Future<_CrudResult> _create(String table, CreatePayload payload) async {
    logger.setTraceProps({'op': 'create', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireTableAccess(table, .create, jwt);
      logger.trace('table_access');

      await _requireRowAccess(table, .create, payload.object, jwt);

      step = 'create_operation';
      final operation = await _createOperation(table, payload, jwt);
      logger.trace('sql_build');

      step = 'sql_execute';
      final (error, result) = await _execute((
        operation.query,
        operation.values,
      ));
      logger.trace('sql_execute');
      if (error != null || result == null) {
        await _extensions.send<NoActionExtensionResponse>(
          ErrorExtensionRequest.create(
            table: table,
            error: error?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        _throwDatabaseError(
          error,
          table: table,
          failure: ([cause]) =>
              RecordCreateFailedException(table: table, cause: cause),
        );
      }

      step = 'sanitize';
      final created = await _sanitizeRow(table, result.rows.single.toMap());
      logger.trace('sanitize');

      step = 'ext_after';
      await _postCreate(table, jwt, object: created);
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return created;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  // TODO: add failed
  Future<void> _postCreate(
    String table,
    Jwt? jwt, {
    required Map<String, Object?> object,
  }) async {
    await _extensions.send<NoActionExtensionResponse>(
      CreateExtensionRequest.afterSuccess(
        table: table,
        object: object,
        jwt: jwt,
      ),
    );
  }

  Future<PerformOperationResponse> _createOperation(
    String table,
    CreatePayload payload,
    Jwt? jwt,
  ) async {
    await _requireRowAccess(table, .create, payload.object, jwt);
    logger.trace('row_access');

    await _requirePhotoReferences(table, payload.object);
    logger.trace('photo_refs');

    await _extensions.send<NoActionExtensionResponse>(
      CreateExtensionRequest.before(
        table: table,
        object: payload.object,
        jwt: jwt,
      ),
    );
    logger.trace('ext_before');

    final changed = await _hashPasswordCreate(table, payload.object);
    if (changed) {
      logger.trace('password_hash');
      if (jwt == null || !jwt.admin.isAdmin || jwt.admin.canEdit == false) {
        throw PasswordUpdateForbiddenException(table: table);
      }
    }

    return await _getOperation(
      CreateOperationRequest(table: table, object: payload.object, jwt: jwt),
    );
  }

  /// Hashes a plain-text password column in [object] in place (the shape the
  /// admin UI sends on row create). Returns whether a password was present and
  /// hashed. Tables without a password column are a no-op.
  Future<bool> _hashPasswordCreate(
    String table,
    Map<String, dynamic> object,
  ) async {
    String? passwordColumnName;
    try {
      final response = await _operations.send<ColumnNameResponse>(
        GetColumnNameRequest(table: table, columnName: .password),
      );
      passwordColumnName = response.name;
    } on MessageHandlerFailedException catch (error) {
      if (error.cause?.contains('No password column on table') case true) {
        return false;
      }
      rethrow;
    } on StateError {
      return false;
    }

    if (passwordColumnName == null ||
        !object.containsKey(passwordColumnName)) {
      return false;
    }

    if (object[passwordColumnName] case final String value) {
      object[passwordColumnName] = await _hashPassword.hash(password: value);
      return true;
    }

    throw InvalidPasswordUpdateException(table: table);
  }

  Future<_CrudListResult> _createMany(
    String table,
    CreateManyPayload payload,
  ) async {
    logger.setTraceProps({'op': 'createMany', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'table_access';
      await _requireTableAccess(table, .create, jwt);
      logger.trace('table_access');

      step = 'row_access';
      for (final object in payload.objects) {
        await _requireRowAccess(table, .create, object, jwt);
      }
      logger.trace('row_access');

      step = 'create_operation';
      final operation = await _createManyOperation(table, payload, jwt);
      logger.trace('sql_build');

      step = 'sql_execute';
      final (error, result) = await _execute((
        operation.query,
        operation.values,
      ));
      logger.trace('sql_execute');
      if (error != null || result == null) {
        await _extensions.send<NoActionExtensionResponse>(
          ErrorExtensionRequest.create(
            table: table,
            error: error?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        _throwDatabaseError(
          error,
          table: table,
          failure: ([cause]) =>
              RecordCreateFailedException(table: table, cause: cause),
        );
      }

      step = 'sanitize';
      final created = await _sanitizeRows(
        table,
        result.rows.map((e) => e.toMap()).toList(),
      );
      logger.trace('sanitize');

      step = 'ext_after';
      for (final object in created) {
        await _postCreate(table, jwt, object: object);
      }
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return created;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<PerformOperationResponse> _createManyOperation(
    String table,
    CreateManyPayload payload,
    Jwt? jwt,
  ) async {
    for (final object in payload.objects) {
      await _requireRowAccess(table, .create, object, jwt);
    }
    logger.trace('row_access');

    for (final object in payload.objects) {
      await _requirePhotoReferences(table, object);
    }
    logger.trace('photo_refs');

    for (final object in payload.objects) {
      await _extensions.send<NoActionExtensionResponse>(
        CreateExtensionRequest.before(table: table, object: object, jwt: jwt),
      );
    }
    logger.trace('ext_before');

    var anyPasswordHashed = false;
    for (final object in payload.objects) {
      if (await _hashPasswordCreate(table, object)) {
        anyPasswordHashed = true;
      }
    }
    if (anyPasswordHashed) {
      logger.trace('password_hash');
      if (jwt == null || !jwt.admin.isAdmin || jwt.admin.canEdit == false) {
        throw PasswordUpdateForbiddenException(table: table);
      }
    }

    return await _getOperation(
      CreateManyOperationRequest(
        table: table,
        objects: payload.objects,
        jwt: jwt,
      ),
    );
  }
}
