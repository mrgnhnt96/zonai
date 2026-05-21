part of zonai_db;

extension _CreateAdminX on ZonaiDb {
  Future<Map<String, Object?>> _createAdmin({
    required String email,
    required String password,
    Map<String, dynamic>? object,
    bool verified = true,
  }) async {
    final collection = await _adminCollectionFor(.password);

    final payload = PasswordAuthPayload(email: email, password: password);
    if (await _hasAuthRecord(collection: collection, payload: payload)) {
      throw StateError('An account with email "$email" already exists');
    }

    final hashedPassword = await _hashPassword.hash(password: password);

    final operation = await _getOperation(
      CreateAuthOperationRequest(
        collection: collection,
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

    var user = await _sanitizeRow(collection, result.rows.single.toMap());

    if (verified) {
      user = await _markAdminVerified(collection: collection, user: user);
    }

    logger.verbose('Created admin account in "$collection"', prefix: _prefix);

    return user;
  }

  Future<Map<String, Object?>> _markAdminVerified({
    required String collection,
    required Map<String, Object?> user,
  }) async {
    final isVerifiedColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: collection, columnName: .isVerified),
    );

    if (user[isVerifiedColumn.name] == true) {
      return user;
    }

    final idColumn = await _operations.send<ColumnNameResponse>(
      GetColumnNameRequest(collection: collection, columnName: .id),
    );

    final userId = user[idColumn.name];
    if (userId is! String) {
      throw StateError('Admin record id not found');
    }

    final operation = await _operations.send<PerformOperationResponse>(
      UpdateOperationRequest(
        collection: collection,
        jwt: null,
        where: Eq(idColumn.name, userId),
        updates: [ColumnUpdate(isVerifiedColumn.name, Literal(true))],
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to mark admin account as verified');
    }

    return {...user, isVerifiedColumn.name: true};
  }
}
