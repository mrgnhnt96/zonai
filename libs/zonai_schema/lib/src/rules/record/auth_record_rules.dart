part of rules;

class AuthRecordRules<T extends AuthCollection<T>> extends BaseRecordRules<T>
    implements Rules<T> {
  const AuthRecordRules(super.schema);

  /// Whether the user can sign up for this record. [canSignUp] is only called
  /// if the record is not yet in the database
  ///
  /// [record] HAS NOT been inserted into the DB yet,
  /// it is the record that will be inserted into the database
  /// if [canSignUp] returns true.
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => true,
    };
  }

  Future<bool> canSignIn(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => true,
    };
  }

  Future<bool> canView(Jwt? jwt, T record) async {
    if (record.id == jwt?.userId) return true;

    return false;
  }

  Future<bool> canUpdate(Jwt? jwt, T record) async {
    if (record.id == jwt?.userId) return true;

    return false;
  }

  Future<bool> canDelete(Jwt? jwt, T record) async {
    if (record.id == jwt?.userId) return true;

    return false;
  }

  Future<bool> canCreate(Jwt? jwt, T record) async {
    if (record.id == jwt?.userId) return true;

    return false;
  }
}
