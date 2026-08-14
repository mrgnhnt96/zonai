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
      final (beforeObjects, :refetchOperation, :updateOperation) =
          await _updateOperation(table, payload, jwt);
      logger.trace('sql_build');

      step = 'sql_execute_update';
      final (updateError, updateResult) = await _execute((
        updateOperation.query,
        updateOperation.values,
      ));
      logger.trace('sql_execute_update');
      if (updateError != null) {
        _throwDatabaseError(
          updateError,
          table: table,
          failure: ([cause]) =>
              RecordUpdateFailedException(table: table, cause: cause),
        );
      }

      if (updateResult == null) {
        throw RecordUpdateFailedException(table: table);
      }

      logger.verbose(
        'Updated ${updateResult.rowsAffected} records',
        prefix: _prefix,
      );

      // `updateResult.rows` always returns empty, need to refetch the records.
      //
      // Nothing matched, so there is nothing to read back and no `IN ()` to
      // build. Returning empty here is what lets the caller say "not found"
      // instead of reporting a failure -- see `DbHandler.update`.
      if (refetchOperation == null) {
        logger.trace('done', extra: {'rows': 0});
        return const [];
      }

      step = 'sql_execute_refetch';
      final (updatedError, updatedResult) = await _execute((
        refetchOperation.query,
        refetchOperation.values,
      ));
      logger.trace(
        'sql_execute_refetch',
        extra: {'rows': updatedResult?.rows.length ?? 0},
      );
      if (updatedError != null || updatedResult == null) {
        await _runExtension(
          ErrorExtensionRequest.update(
            table: table,
            error: updatedError?.toString() ?? 'Unknown error',
            jwt: jwt,
          ),
        );

        _throwDatabaseError(
          updatedError,
          table: table,
          failure: ([cause]) =>
              RecordUpdateFailedException(table: table, cause: cause),
        );
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
    final passwordColumnName = await _cachedColumnName(table, .password);
    if (passwordColumnName == null) {
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
            } else {
              throw InvalidPasswordUpdateException(table: table);
            }
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
    await _runExtension(
      AfterUpdateExtensionRequest(
        table: table,
        before: before,
        after: after,
        jwt: jwt,
      ),
    );
  }

  /// The read-back for [_update], keyed by the rows the pre-update read found
  /// rather than by [payload]'s `where`.
  ///
  /// Replaying the `where` after the write cannot see a row the update just
  /// moved out of it -- `WHERE status = 'open'` while setting `status =
  /// 'closed'` matches nothing on the second pass. The write had already
  /// committed, so the caller got a failure for an update that succeeded, and
  /// [AfterUpdateExtensionRequest] got a `before`/`after` pair of different
  /// lengths (its assert names exactly this).
  ///
  /// `null` means the pre-update read matched nothing: no rows to read back,
  /// and no `IN ()` to build, which is not valid SQL.
  ///
  /// Narrow remaining gap, deliberately not handled: an update that rewrites
  /// the id column itself moves the rows out of *this* clause too. Nothing in
  /// the codebase does that, and a table whose ids are reassigned by an update
  /// has no stable way to be read back at all.
  Future<PerformOperationResponse?> _refetchOperation(
    String table,
    UpdatePayload payload,
    List<Map<String, Object?>> before,
    Jwt? jwt,
  ) async {
    if (before.isEmpty) return null;

    final idColumn = await _cachedColumnName(table, .id);
    if (idColumn == null) {
      // No id column to key on. Nothing in this repo's schemas is shaped that
      // way; if one ever is, replaying the where is still better than no
      // read-back, and it is correct whenever the update leaves the matched
      // columns alone.
      return _getOperation(
        ListOperationRequest(
          table: table,
          where: payload.where,
          limit: payload.limit,
          offset: null,
          jwt: jwt,
        ),
      );
    }

    final ids = [
      for (final row in before)
        if (row[idColumn] case final Object id) id,
    ];
    if (ids.isEmpty) return null;

    return _getOperation(
      ListOperationRequest(
        table: table,
        where: In(idColumn, ids),
        limit: null,
        offset: null,
        jwt: jwt,
      ),
    );
  }

  Future<
    (
      List<Map<String, Object?>>, {
      PerformOperationResponse? refetchOperation,
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
    logger.trace(
      'sql_execute_read',
      extra: {'rows': readResult?.rows.length ?? 0},
    );
    if (readError != null) {
      _throwDatabaseError(
        readError,
        table: table,
        failure: ([cause]) =>
            RecordReadFailedException(table: table, cause: cause),
      );
    }

    if (readResult == null) {
      throw RecordReadFailedException(table: table);
    }

    final objects = readResult.rows.map((e) => e.toMap()).toList();

    for (final row in objects) {
      // Pre-password-hash payload: canUpdate's simulated `after` shows the
      // plaintext for a password-column update, not the hash that will
      // actually be written (hashing happens later, in
      // _hashPasswordUpdates). Narrow, pre-existing-adjacent gap — rules
      // don't gate on the password column today.
      // TODO(future): if a table ever needs canUpdate to see the post-hash
      // value, this check would need to move after _hashPasswordUpdates —
      // not done here since no consumer needs it yet and it changes the
      // fail-fast ordering of the rules gate.
      await _requireRowAccess(
        table,
        .update,
        row,
        jwt,
        updates: payload.updates,
      );
    }
    logger.trace('row_access');

    final sanitizedBefore = await _sanitizeRows(table, objects, jwt: jwt);

    await _requirePhotoReferencesFromUpdates(table, payload.updates);

    await _runExtension(
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

    // Built from the rows just read, not from `payload.where` -- see
    // [_refetchOperation]. Deliberately built *before* the write runs, so the
    // ids it keys on are the ones the rules gate above actually admitted.
    final refetch = await _refetchOperation(table, payload, objects, jwt);

    return (
      sanitizedBefore,
      refetchOperation: refetch,
      updateOperation: operation,
    );
  }
}
