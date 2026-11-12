part of zonai_db;

/// One batch step after its checks: the SQL it will run, and what its
/// `after*Success` hooks need once the batch commits.
sealed class _BatchStep {
  _BatchStep(this.operation);

  final BatchOperation operation;

  String get table => operation.table;

  /// Rows written, set by [_BatchX._batchExecute] inside the transaction.
  int count = 0;

  /// The rows a create returned or an update read back, raw, set inside the
  /// transaction and sanitized after it commits.
  List<Map<String, Object?>> written = const [];
}

final class _BatchCreateStep extends _BatchStep {
  _BatchCreateStep(super.operation, {required this.insert});

  final PerformOperationResponse insert;
}

final class _BatchUpdateStep extends _BatchStep {
  _BatchUpdateStep(
    super.operation, {
    required this.before,
    required this.update,
    required this.refetch,
    required this.expect,
  });

  /// The rows the update was authorized for, sanitized, as hooks see them.
  final List<Map<String, Object?>> before;
  final PerformOperationResponse update;

  /// `null` when nothing matched: there is nothing to write or read back.
  final PerformOperationResponse? refetch;
  final Where? expect;
}

final class _BatchDeleteStep extends _BatchStep {
  _BatchDeleteStep(
    super.operation, {
    required this.objects,
    required this.delete,
  });

  /// The rows the delete was authorized for, sanitized, as hooks see them.
  final List<Map<String, Object?>> objects;
  final PerformOperationResponse delete;
}

extension _BatchX on ZonaiDb {
  /// Refuses a batch that is malformed before anything is admitted, so a
  /// refusal costs nothing and is answered `400`, not remapped by [_run].
  void _requireBatchShape(List<BatchOperation> operations) {
    if (operations.length > BatchBody.maxOperations) {
      throw InvalidBodyException(
        'BatchBody: ${operations.length} operations is more than the '
        '${BatchBody.maxOperations} one batch may carry; split it',
      );
    }

    for (final operation in operations) {
      // Deleting a `_photos` row deletes its file while the delete is being
      // checked, long before the transaction. A batch that then rolled back
      // would keep the row and lose the file.
      if (operation case BatchDelete() || BatchDeleteMany()
          when operation.table == '_photos') {
        throw InvalidBodyException(
          'BatchBody: a batch cannot delete from "_photos", because the '
          'photo files cannot be restored if the batch rolls back; delete '
          'photos with their own request',
        );
      }
    }
  }

  /// Hashes every create step's plain-text password, before the writer lock
  /// as [ZonaiDb.create] does. Update steps hash theirs while being checked,
  /// as a single update does.
  Future<void> _hashBatchPasswords(
    List<BatchOperation> operations,
    Jwt? jwt,
  ) async {
    for (final operation in operations) {
      final objects = switch (operation) {
        BatchCreate(:final body) => [body.object],
        BatchCreateMany(:final body) => body.objects,
        _ => const <Map<String, dynamic>>[],
      };

      var hashed = false;
      for (final object in objects) {
        if (await _hashPasswordCreate(operation.table, object)) hashed = true;
      }

      if (hashed &&
          (jwt == null || !jwt.admin.isAdmin || jwt.admin.canEdit == false)) {
        throw PasswordUpdateForbiddenException(table: operation.table);
      }
    }
  }

  Future<List<BatchResult>> _batch(
    List<BatchOperation> operations,
    Jwt? jwt,
  ) async {
    logger.setTraceProps({'op': 'batch', 'steps': '${operations.length}'});
    var step = 'start';
    logger.trace('start');
    try {
      // Every step is checked before any of them runs. The checks read the
      // database as it was before the batch -- a rule or hook in a worker
      // reads over IPC, and could not see an open transaction anyway.
      step = 'prepare';
      final steps = <_BatchStep>[];
      for (final operation in operations) {
        steps.add(await _batchPrepare(operation, jwt));
      }
      logger.trace('prepare');

      step = 'sql_execute';
      await _batchExecute(steps, jwt);
      logger.trace('sql_execute');

      // Committed. From here on, as for a single write, a failing hook is
      // logged and the writes stand.
      step = 'sanitize';
      final results = <BatchResult>[];
      for (final prepared in steps) {
        final rows = switch (prepared) {
          _BatchCreateStep() => await _sanitizeRows(
            prepared.table,
            prepared.written,
          ),
          _BatchUpdateStep() => await _sanitizeRows(
            prepared.table,
            prepared.written,
            jwt: jwt,
          ),
          // A delete route returns no rows; nor does its step.
          _BatchDeleteStep() => const <Map<String, Object?>>[],
        };
        results.add(
          BatchResult(
            op: prepared.operation.op,
            table: prepared.table,
            count: prepared.count,
            rows: rows,
          ),
        );
      }
      logger.trace('sanitize');

      step = 'ext_after';
      for (final (i, prepared) in steps.indexed) {
        final table = prepared.table;
        final rows = results[i].rows;
        switch (prepared) {
          case _BatchCreateStep():
            for (final row in rows) {
              await _postCreate(table, jwt, object: row);
            }
          case _BatchUpdateStep(:final before):
            if (rows.isNotEmpty) {
              await _postUpdate(
                table,
                jwt,
                before: await _batchStillPresent(table, before, rows),
                after: rows,
              );
            }
          case _BatchDeleteStep(:final objects, :final count):
            if (count > 0) {
              await _postDelete(table, jwt, objects: objects);
            }
        }
      }
      logger.trace('ext_after');

      step = 'effects';
      await _executeEffects();
      logger.trace('done');

      return results;
    } catch (e) {
      logger.trace('FAILED at $step: ${e.runtimeType}');
      rethrow;
    }
  }

  /// The rows of [before] still in [after]. An earlier step in the batch may
  /// have deleted some of the rows an update was checked against, and
  /// `afterUpdate` pairs `before` with `after` one to one.
  Future<List<Map<String, Object?>>> _batchStillPresent(
    String table,
    List<Map<String, Object?>> before,
    List<Map<String, Object?>> after,
  ) async {
    if (before.length == after.length) return before;
    final idColumn = await _cachedColumnName(table, .id);
    if (idColumn == null) return before;
    final present = {for (final row in after) row[idColumn]};
    return [
      for (final row in before)
        if (present.contains(row[idColumn])) row,
    ];
  }

  /// Runs [operation]'s checks and builds its SQL, the same way its single
  /// write does, without writing anything.
  Future<_BatchStep> _batchPrepare(BatchOperation operation, Jwt? jwt) async {
    final table = operation.table;
    switch (operation) {
      case BatchCreate(:final body):
        await _requireTableAccess(table, .create, jwt);
        final insert = await _createOperation(
          table,
          CreatePayload(object: body.object),
          jwt,
        );
        return _BatchCreateStep(operation, insert: insert);

      case BatchCreateMany(:final body):
        await _requireTableAccess(table, .create, jwt);
        final insert = await _createManyOperation(
          table,
          CreateManyPayload(objects: body.objects),
          jwt,
        );
        return _BatchCreateStep(operation, insert: insert);

      case BatchUpdate(body: final UpdateBody body) ||
          BatchUpdateMany(:final body):
        final (
          before,
          :refetchOperation,
          :updateOperation,
        ) = await _updateOperation(
          table,
          UpdatePayload(
            where: body.where,
            updates: body.updates,
            limit: body.limit,
            expect: body.expect,
          ),
          jwt,
        );
        // `PATCH /db` answers 404 when nothing matches; so does its step.
        if (operation is BatchUpdate && before.isEmpty) {
          throw RecordNotFoundException(table: table);
        }
        return _BatchUpdateStep(
          operation,
          before: before,
          update: updateOperation,
          refetch: refetchOperation,
          expect: body.expect,
        );

      case BatchDelete(body: final DeleteBody body) ||
          BatchDeleteMany(:final body):
        // A one-row delete that matches nothing throws not-found here.
        final (objects, :deleteOperation) = await _deleteOperation(
          table,
          DeletePayload(where: body.where, limit: body.limit),
          jwt,
        );
        return _BatchDeleteStep(
          operation,
          objects: objects,
          delete: deleteOperation,
        );
    }
  }

  /// Runs every step's SQL in one transaction. The first failure rolls the
  /// whole batch back and is thrown as that step's own exception.
  Future<void> _batchExecute(List<_BatchStep> steps, Jwt? jwt) async {
    await open();
    final db = this.db;
    if (db == null) {
      throw const DatabaseNotOpenException();
    }

    (_BatchStep, Object)? failed;
    try {
      await db.transaction((tx) async {
        for (final step in steps) {
          try {
            switch (step) {
              case _BatchCreateStep(:final insert):
                final result = OperationResult(
                  await tx.execute(insert.query, insert.values),
                );
                step.count = result.rows.length;
                step.written = [for (final row in result.rows) row.toMap()];

              case _BatchUpdateStep(
                :final update,
                :final refetch?,
                :final expect,
                :final before,
              ):
                final written = await tx.execute(update.query, update.values);
                // `expect` rides the UPDATE. A row an earlier step changed so
                // it no longer meets `expect` is skipped by SQL; refuse the
                // batch rather than report a partial update as done.
                if (expect != null && written.rowsAffected != before.length) {
                  throw PreconditionFailedException(
                    table: step.table,
                    current: const [],
                  );
                }
                final read = OperationResult(
                  await tx.execute(refetch.query, refetch.values),
                );
                step.count = written.rowsAffected;
                step.written = [for (final row in read.rows) row.toMap()];

              case _BatchUpdateStep():
                break;

              case _BatchDeleteStep(:final delete, :final objects)
                  when objects.isNotEmpty:
                final result = await tx.execute(delete.query, delete.values);
                step.count = result.rowsAffected;

              case _BatchDeleteStep():
                break;
            }
          } catch (e) {
            failed = (step, e);
            rethrow;
          }
        }
      });
    } catch (e) {
      final (step, error) = failed ?? (null, e);
      // Not a step's failure (the COMMIT itself): [_run] maps it.
      if (step == null) rethrow;
      if (error is CrudException) throw error;
      await _batchErrorExtension(step, error, jwt);
      _throwDatabaseError(
        error,
        table: step.table,
        failure: ([cause]) => switch (step) {
          _BatchCreateStep() => RecordCreateFailedException(
            table: step.table,
            cause: cause,
          ),
          _BatchUpdateStep() => RecordUpdateFailedException(
            table: step.table,
            cause: cause,
          ),
          _BatchDeleteStep() => RecordDeleteFailedException(
            table: step.table,
            cause: cause,
          ),
        },
      );
    }
  }

  /// The `afterError` hook for the step whose SQL failed, after the rollback.
  Future<void> _batchErrorExtension(
    _BatchStep step,
    Object error,
    Jwt? jwt,
  ) async {
    final table = step.table;
    await _runExtension(switch (step) {
      _BatchCreateStep() => ErrorExtensionRequest.create(
        table: table,
        error: '$error',
        jwt: jwt,
      ),
      _BatchUpdateStep() => ErrorExtensionRequest.update(
        table: table,
        error: '$error',
        jwt: jwt,
      ),
      _BatchDeleteStep() => ErrorExtensionRequest.delete(
        table: table,
        error: '$error',
        jwt: jwt,
      ),
    });
  }
}
