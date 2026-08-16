part of zonai_db;

extension _RemoveAdminX on ZonaiDb {
  /// [actingAdmin] is `null` for the trusted CLI path (`zonai db admin
  /// remove`), which has no signed-in caller to check for self-removal
  /// against. The last-admin guard (design §4 item 6) applies either way --
  /// it protects the table's invariant, not just the dashboard's.
  Future<Map<String, Object?>> _removeAdmin({
    required String email,
    Jwt? actingAdmin,
  }) async {
    final (table, _) = await _adminTable();

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

    if (actingAdmin != null &&
        actingAdmin.table == table &&
        actingAdmin.userId.value == userId) {
      throw const CannotRemoveSelfAsAdminException();
    }

    final remainingAdmins = await _listAdmins();
    if (remainingAdmins.length <= 1) {
      throw LastAdminCannotBeRemovedException(table: table);
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

    await _revokeAllSessions(UnknownId(userId));

    logger.verbose('Removed admin account from "$table"', prefix: _prefix);

    return _sanitizeRow(table, user);
  }
}
