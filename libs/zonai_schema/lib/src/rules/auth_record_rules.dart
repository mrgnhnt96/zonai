part of rules;

class AuthRecordRules<T extends AuthCollection<T>> extends RecordRules<T> {
  AuthRecordRules(super.schema);

  /// Whether the user can sign up for this record. [canSignUp] is only called
  /// if the record is not yet in the database
  ///
  /// [record] HAS NOT been inserted into the DB yet,
  /// it is the record that will be inserted into the database
  /// if [canSignUp] returns true.
  Future<bool> canSignUp(Request request, T record) async {
    return switch (record.authType) {
      PasswordAuth() => request.user.isSuperUser,
    };
  }

  Future<bool> canView(Request request, T record) async {
    if (request.user.isSuperUser) return true;
    if (record.id == request.user.id) return true;

    return false;
  }

  Future<bool> canUpdate(Request request, T record) async {
    if (request.user.isSuperUser) return true;
    if (record.id == request.user.id) return true;

    return false;
  }

  Future<bool> canDelete(Request request, T record) async {
    if (request.user.isSuperUser) return true;
    if (record.id == request.user.id) return true;

    return false;
  }

  Future<bool> canCreate(Request request, T record) async {
    if (request.user.isSuperUser) return true;

    return false;
  }
}
