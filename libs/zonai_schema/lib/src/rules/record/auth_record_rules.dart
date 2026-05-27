part of rules;

class AuthRecordRules<S extends AuthTable<R>, R>
    extends BaseRecordRules<S, R>
    implements Rules<S, R> {
  const AuthRecordRules(super.schema);

  /// Whether the user can sign up for this record. [canSignUp] is only called
  /// if the record is not yet in the database
  ///
  /// [record] HAS NOT been inserted into the DB yet,
  /// it is the record that will be inserted into the database
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

  Future<bool> canView(Jwt? jwt, R record) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;

    return _rowIdMatches(record, jwtUserId);
  }

  Future<bool> canUpdate(Jwt? jwt, R record) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    return _rowIdMatches(record, jwtUserId);
  }

  Future<bool> canDelete(Jwt? jwt, R record) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    return _rowIdMatches(record, jwtUserId);
  }

  Future<bool> canCreate(Jwt? jwt, R record) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    return _rowIdMatches(record, jwtUserId);
  }

  bool _rowIdMatches(R record, UnknownId jwtUserId) {
    try {
      final rowId = schema.id.$.readValueOf(record);
      return rowId is Id && rowId.value == jwtUserId.value;
    } catch (_) {
      return false;
    }
  }
}
