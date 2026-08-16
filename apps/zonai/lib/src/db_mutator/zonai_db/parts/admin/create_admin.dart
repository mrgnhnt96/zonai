part of zonai_db;

extension _CreateAdminX on ZonaiDb {
  /// Creates an admin row in [table], or in the first configured `AsAdmin`
  /// table when none is named — which is what `zonai db admin add` wants,
  /// having nothing else to go on.
  ///
  /// [_acceptAdminInvite] names one: an invite belongs to the table it was
  /// issued for, and the two stop being the same table the moment a project
  /// declares a second `AsAdmin` collection.
  Future<Map<String, Object?>> _createAdmin({
    required String email,
    String? inTable,
    String? password,
    Map<String, dynamic>? object,
    bool verified = true,
  }) async {
    final (table, authTypes) = switch (inTable) {
      null => await _adminTable(),
      final named => (named, await _adminTableAuthTypes(named)),
    };
    final supportsPassword = authTypes.contains(AuthType.password);

    if (supportsPassword && password == null) {
      throw ArgumentError(
        'Admin table "$table" supports password sign-in and requires a '
        'password',
      );
    }
    if (!supportsPassword && password != null) {
      throw ArgumentError(
        'Admin table "$table" has no password sign-in configured; omit '
        'the password -- this account signs in through its other '
        'configured auth type instead',
      );
    }

    // Only used to look up an existing record by email (_hasAuthRecord
    // never reads the password itself); a placeholder is fine when the
    // table has no password to check.
    final dedupPayload = PasswordAuthPayload(
      email: email,
      password: password ?? '',
    );
    if (await _hasAuthRecord(table: table, payload: dedupPayload)) {
      throw StateError('An account with email "$email" already exists');
    }

    final hashedPassword = password == null
        ? null
        : await _hashPassword.hash(password: password);

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        table: table,
        jwt: null,
        payload: PasswordAuthOperationPayload.save(
          email: email,
          passwordHash: hashedPassword,
          object: object,
        ),
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to create admin account');
    }

    var user = await _sanitizeRow(table, result.rows.single.toMap());

    if (verified) {
      user = await _markAdminVerified(table: table, user: user);
    }

    logger.verbose('Created admin account in "$table"', prefix: _prefix);

    return user;
  }

  Future<Map<String, Object?>> _markAdminVerified({
    required String table,
    required Map<String, Object?> user,
  }) async {
    final isVerifiedColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .isVerified),
    );

    if (user[isVerifiedColumn.name] == true) {
      return user;
    }

    final idColumn = await _dispatchOperation<ColumnNameResponse>(
      GetColumnNameRequest(table: table, columnName: .id),
    );

    final userId = user[idColumn.name];
    if (userId is! String) {
      throw StateError('Admin record id not found');
    }

    final isVerifiedColumnName = isVerifiedColumn.name;
    final idColumnName = idColumn.name;

    if (isVerifiedColumnName == null || idColumnName == null) {
      logger.warn(
        'Missing column name for admin verification | id: $idColumnName, isVerified: $isVerifiedColumnName',
      );
      return user;
    }

    final operation = await _dispatchOperation<PerformOperationResponse>(
      UpdateOperationRequest(
        table: table,
        jwt: null,
        where: Eq(idColumnName, userId),
        updates: [ColumnUpdate(isVerifiedColumnName, Literal(true))],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to mark admin account as verified');
    }

    return {...user, isVerifiedColumnName: true};
  }
}
