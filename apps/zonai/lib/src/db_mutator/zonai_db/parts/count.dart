part of zonai_db;

extension _CountX on ZonaiDb {
  Future<int> _count(String collection, CountPayload payload) async {
    final jwt = await _extractJwt(payload);
    await _requireCollectionAccess(collection, .list, jwt);

    final operation = await _getOperation(
      CountOperationRequest(
        collection: collection,
        where: payload.where,
        jwt: jwt,
      ),
    );

    final (error, result) = await _execute((operation.query, operation.values));
    if (error != null || result == null) {
      throw error ?? StateError('Failed to count records');
    }

    return result.rows.length;
  }
}
