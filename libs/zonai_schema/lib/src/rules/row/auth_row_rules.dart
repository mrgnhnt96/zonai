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
  ///
  /// ## Sign-up is CLOSED by default on an [AsAdmin] table
  ///
  /// `AsAdmin` is not a marker for "some rows here may be admins" — the
  /// framework hands `isAdmin` to EVERY row the table authenticates
  /// (`DbOperations._getJwtConfig`: `isAdmin: admin != null`, with no
  /// per-row predicate anywhere). So an `AsAdmin` table whose sign-up is
  /// open makes every registrant an admin, and `POST /auth/sign-up` is
  /// anonymous by design.
  ///
  /// Neither half is wrong alone, which is why nothing caught the pair: a
  /// developer reaches for `AsAdmin` to get `admin.isAdmin` on the JWT and
  /// inherits an open sign-up they never wrote. The combination therefore
  /// fails CLOSED here rather than quietly granting.
  ///
  /// An app that genuinely wants open registration on an admin table has to
  /// say so, and the override is the place a reviewer will look:
  ///
  /// ```dart
  /// final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  ///   AdminRowRules() : super(admins);
  ///
  ///   // Deliberate: this table is AsAdmin, so anyone who signs up is an
  ///   // admin. Fine for a demo, never for production.
  ///   @override
  ///   Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
  /// }
  /// ```
  ///
  /// Bootstrapping is unaffected: `zonai db admin create` writes through the
  /// operations worker and never consults this rule, and an existing admin
  /// still passes on the `jwt.admin.isAdmin` branch below.
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async {
    if (jwt?.admin.isAdmin case true) {
      return true;
    }

    if (schema is AsAdmin) {
      return false;
    }

    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => schema is OtpAuth,
      .magicLink => schema is MagicLinkAuth,
      .oauth => schema is OAuth,
    };
  }

  Future<bool> canSignIn(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => schema is OtpAuth,
      .magicLink => schema is MagicLinkAuth,
      .oauth => schema is OAuth,
    };
  }

  Future<bool> canPasswordReset(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => false,
      .magicLink => false,
      .oauth => false,
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
