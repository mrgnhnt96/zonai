part of zonai_db;

extension _UpdateX on ZonaiDb {
  Future<_CrudListResult> _update(
    String table,
    UpdatePayload payload, {
    Jwt? userJwt,
  }) async {
    logger.setTraceProps({'op': 'update', 'table': table});
    var step = 'start';
    logger.trace('start');
    try {
      step = 'jwt_extract';
      final jwt = userJwt ?? await _extractJwt(payload);
      logger.trace('jwt_extract');

      step = 'update_operation';
      final (beforeObjects, :readOperation, :updateOperation) =
          await _updateOperation(table, payload, jwt);
      logger.trace('sql_build');

      step = 'sql_execute_update';
      final (updateError, updateResult) = await _execute((
        updateOperation.query,
        updateOperation.values,
      ));
      logger.trace('sql_execute_update');
      if (updateError != null) {
        throw updateError;
      }

      if (updateResult == null) {
        throw RecordUpdateFailedException(table: table);
      }

      logger.verbose(
        'Updated ${updateResult.rowsAffected} records',
        prefix: _prefix,
      );

      // `updateResult.rows` always returns empty, need to refetch the records
      step = 'sql_execute_refetch';
      final (updatedError, updatedResult) = await _execute((
        readOperation.query,
        readOperation.values,
      ));
      logger.trace('sql_execute_refetch', extra: {'rows': updatedResult?.rows.length ?? 0});
      if (updatedError != null || updatedResult == null) {
        await _extensions.send<NoActionExtensionResponse>(
          ErrorExtensionRequest.update(
            table: table,
            error: updatedError?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        throw updatedError ?? RecordUpdateFailedException(table: table);
      }

      final updatedObjects = updatedResult.rows.map((e) => e.toMap()).toList();

      step = 'sanitize';
      final sanitizedUpdated = await _sanitizeRows(
        table,
        updatedObjects,
        jwt: jwt,
      );
      logger.trace('sanitize');

      step = 'ext_after';
      await _postUpdate(
        table,
        jwt,
        before: beforeObjects,
        after: sanitizedUpdated,
      );
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done', extra: {'rows': updateResult.rowsAffected});

      return sanitizedUpdated;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<(List<Update>, bool)> _hashPasswordUpdates(
    String table,
    List<Update> updates,
  ) async {
    String? passwordColumnName;
    try {
      final response = await _operations.send<ColumnNameResponse>(
        GetColumnNameRequest(table: table, columnName: .password),
      );
      passwordColumnName = response.name;
    } on StateError {
      return (updates, false);
    }

    var changed = false;
    final result = <Update>[];
    for (final update in updates) {
      switch (update) {
        case ColumnUpdate(:final column) when column == passwordColumnName:
          if (update.value case Literal(:final String value)) {
            final hashed = await _hashPassword.hash(password: value);
            result.add(ColumnUpdate(column, Literal(hashed)));
            changed = true;
          } else {
            throw InvalidPasswordUpdateException(table: table);
          }
        case ObjectUpdate(:final object):
          if (object.containsKey(passwordColumnName)) {
            if (object[passwordColumnName] case final String value) {
              final hashed = await _hashPassword.hash(password: value);
              object[passwordColumnName] = hashed;
              changed = true;
              continue;
            }

            throw InvalidPasswordUpdateException(table: table);
          }

          result.add(update);
        case ColumnUpdate():
          result.add(update);
      }
    }

    return (result, changed);
  }

  Future<void> _postUpdate(
    String table,
    Jwt? jwt, {
    required List<Map<String, Object?>> before,
    required List<Map<String, Object?>> after,
  }) async {
    await _extensions.send<NoActionExtensionResponse>(
      AfterUpdateExtensionRequest(
        table: table,
        before: before,
        after: after,
        jwt: jwt,
      ),
    );
  }

  Future<
    (
      List<Map<String, Object?>>, {
      PerformOperationResponse readOperation,
      PerformOperationResponse updateOperation,
    })
  >
  _updateOperation(String table, UpdatePayload payload, Jwt? jwt) async {
    await _requireTableAccess(table, .update, jwt);
    logger.trace('table_access');

    final readOperation = await _getOperation(
      ListOperationRequest(
        table: table,
        where: payload.where,
        limit: payload.limit,
        offset: null,
        jwt: jwt,
      ),
    );

    final (readError, readResult) = await _execute((
      readOperation.query,
      readOperation.values,
    ));
    logger.trace('sql_execute_read', extra: {'rows': readResult?.rows.length ?? 0});
    if (readError != null) {
      throw readError;
    }

    if (readResult == null) {
      throw RecordReadFailedException(table: table);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      await _requireRowAccess(table, .update, row, jwt);
    }
    logger.trace('row_access');

    final sanitizedBefore = await _sanitizeRows(table, objects, jwt: jwt);

    await _requirePhotoReferencesFromUpdates(table, payload.updates);

    await _extensions.send<NoActionExtensionResponse>(
      BeforeUpdateExtensionRequest(
        table: table,
        objects: sanitizedBefore,
        jwt: jwt,
      ),
    );
    logger.trace('ext_before');

    final (updates, changed) = await _hashPasswordUpdates(
      table,
      payload.updates,
    );
    if (changed) {
      logger.trace('password_hash');
      if (jwt == null || !jwt.admin.isAdmin || jwt.admin.canEdit == false) {
        throw PasswordUpdateForbiddenException(table: table);
      }
    }

    final operation = await _getOperation(
      UpdateOperationRequest(
        table: table,
        where: payload.where,
        updates: updates,
        jwt: jwt,
      ),
    );

    return (
      sanitizedBefore,
      readOperation: readOperation,
      updateOperation: operation,
    );
  }
}
