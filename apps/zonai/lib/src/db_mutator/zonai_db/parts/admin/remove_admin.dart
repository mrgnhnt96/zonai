part of zonai_db;

extension _RemoveAdminX on ZonaiDb {
  Future<Map<String, Object?>> _removeAdmin({required String email}) async {
    final table = await _adminCollectionFor(.password);

    final user = await _authRecord(table: table, email: email, sanitize: false);
    if (user == null) {
      throw StateError('No admin account with email "$email" exists');
    }

    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );
    final idColumnName = idColumn.name;
    if (idColumnName == null) {
      throw StateError('Missing id column for admin removal');
    }

    final userId = user[idColumnName];
    if (userId is! String) {
      throw StateError('Admin record id not found');
    }

    final operation = await _dispatchOperation<PerformOperationResponse>(
      DeleteOperationRequest(
        table: table,
        where: Eq(idColumnName, userId),
        limit: 1,
        jwt: null,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to remove admin account');
    }

    logger.verbose('Removed admin account from "$table"', prefix: _prefix);

    return _sanitizeRow(table, user);
  }
}
