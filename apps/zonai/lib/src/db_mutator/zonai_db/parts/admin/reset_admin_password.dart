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

    // The safety belongs to the METHOD, not to whoever calls it. A reset is
    // the remedy for a password someone else may know, so the sessions that
    // password minted must not outlive it -- otherwise an attacker's JWT
    // keeps working, for the whole of `jwtExpiresIn` (14 days by default),
    // against an account whose owner believes they have just locked them out.
    //
    // `zonai db admin reset-password` happens to revoke today, but only as a
    // side effect of ALSO calling `requirePasswordReset`, which
    // `--no-force-reset` turns off -- and any future caller of this method
    // would inherit the gap. Same revocation as [_logoutAll], admin removal,
    // [_requirePasswordReset] and [_confirmResetPassword]; it is a plain
    // DELETE, so running it twice on one CLI invocation is harmless and the
    // second call simply counts zero.
    final revoked = await _revokeAllSessions(UnknownId(userId));

    logger.verbose(
      'Reset admin password in "$table", revoked $revoked session(s)',
      prefix: _prefix,
    );

    return _sanitizeRow(table, user);
  }
}
