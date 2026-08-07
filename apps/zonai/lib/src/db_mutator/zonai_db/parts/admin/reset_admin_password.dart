part of zonai_db;

extension _ResetAdminPasswordX on ZonaiDb {
  Future<Map<String, Object?>> _resetAdminPassword({
    required String email,
    required String newPassword,
  }) async {
    final table = await _adminCollectionFor(.password);

    final user = await _authRecord(table: table, email: email, sanitize: false);
    if (user == null) {
      throw StateError('No admin account with email "$email" exists');
    }

    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );
    final passwordColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .password),
    );

    final idColumnName = idColumn.name;
    final passwordColumnName = passwordColumn.name;
    if (idColumnName == null || passwordColumnName == null) {
      throw StateError('Missing column(s) for admin password reset');
    }

    final userId = user[idColumnName];
    if (userId is! String) {
      throw StateError('Admin record id not found');
    }

    final newPasswordHash = await _hashPassword.hash(password: newPassword);

    final operation = await _dispatchOperation<PerformOperationResponse>(
      UpdateOperationRequest(
        table: table,
        jwt: null,
        where: Eq(idColumnName, userId),
        updates: [ColumnUpdate(passwordColumnName, Literal(newPasswordHash))],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to reset admin password');
    }

    logger.verbose('Reset admin password in "$table"', prefix: _prefix);

    return _sanitizeRow(table, user);
  }
}
