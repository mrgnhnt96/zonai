part of rules;

class AuthRowRules<S extends AuthTable<R>, R> extends BaseRowRules<S, R>
    implements Rules<S, R> {
  const AuthRowRules(super.schema);

  /// Whether the user can sign up for this row. [canSignUp] is only called
  /// if the row is not yet in the database
  ///
  /// [row] HAS NOT been inserted into the DB yet,
  /// it is the row that will be inserted into the database
  /// if [canSignUp] returns true.
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => schema is OtpAuth,
      .magicLink => schema is MagicLinkAuth,
    };
  }

  Future<bool> canSignIn(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => schema is OtpAuth,
      .magicLink => schema is MagicLinkAuth,
    };
  }

  Future<bool> canPasswordReset(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => false,
      .magicLink => false,
    };
  }

  Future<bool> canView(Jwt? jwt, R row) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;

    return _rowIdMatches(row, jwtUserId);
  }

  Future<bool> canUpdate(Jwt? jwt, R before, R after) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    return _rowIdMatches(before, jwtUserId);
  }

  Future<bool> canDelete(Jwt? jwt, R row) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    return _rowIdMatches(row, jwtUserId);
  }

  Future<bool> canCreate(Jwt? jwt, R row) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    return _rowIdMatches(row, jwtUserId);
  }

  bool _rowIdMatches(R row, UnknownId jwtUserId) {
    try {
      final rowId = schema.id.readValueOf(row);
      return rowId is Id && rowId.value == jwtUserId.value;
    } catch (_) {
      return false;
    }
  }
}
