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
  /// Bootstrapping is unaffected: `zonai db admin add` writes through the
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
      .anonymous => schema is AnonymousAuth,
    };
  }

  /// [AuthType.anonymous] here is resuming an anonymous account with its
  /// device credential (`POST /auth/anonymous/resume`).
  Future<bool> canSignIn(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => schema is OtpAuth,
      .magicLink => schema is MagicLinkAuth,
      .oauth => schema is OAuth,
      .anonymous => schema is AnonymousAuth,
    };
  }

  Future<bool> canPasswordReset(Jwt? jwt, AuthType authType) async {
    return switch (authType) {
      .password => schema is PasswordAuth,
      .otp => false,
      .magicLink => false,
      .oauth => false,
      .anonymous => false,
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

  /// On an [AnonymousAuth] table the owner may not change their own email or
  /// verification flag. Those are written by the upgrade flow alone, after
  /// the new address is proven. A self-written address would sit unverified
  /// on a row the writer still holds a credential for, and the address's
  /// real owner signing in by OTP would land in it.
  Future<bool> canUpdate(Jwt? jwt, R before, R after) async {
    if (jwt?.admin.canEdit case true) {
      return true;
    }

    final jwtUserId = jwt?.userId;
    if (jwtUserId == null) return false;
    if (!_rowIdMatches(before, jwtUserId)) return false;

    // The owner may edit their row, but not the columns the auth flows own.
    // `is_verified` is what email verification proves, and `email` is what it
    // proved it FOR; letting a user write either directly skips the proof.
    // An app that opens `canUpdate` at the table level for profile edits used
    // to hand both out with it. There is no self-service email change yet --
    // an admin, or an override of this method, is the way to change one.
    //
    // An anonymous row needs its own check first: the text comparison below
    // reads a NULL address as "null", so an anonymous owner writing the
    // string 'null' would pass it as "unchanged".
    if (schema case final AnonymousAuth anonymous) {
      if (_identityChanged(anonymous, before, after)) return false;
    }
    return !_changesAuthOwnedColumns(before, after);
  }

  bool _changesAuthOwnedColumns(R before, R after) {
    if (schema case final HasEmail auth) {
      final emailBefore = auth.email.readValueOf(before);
      final emailAfter = auth.email.readValueOf(after);
      if ('$emailBefore'.toLowerCase() != '$emailAfter'.toLowerCase()) {
        return true;
      }
      if (auth.isVerified.readValueOf(before) !=
          auth.isVerified.readValueOf(after)) {
        return true;
      }
    }
    return false;
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

  /// Fails closed: a column that cannot be read counts as changed.
  bool _identityChanged(AnonymousAuth table, R before, R after) {
    try {
      return table.email.readValueOf(before) !=
              table.email.readValueOf(after) ||
          table.isVerified.readValueOf(before) !=
              table.isVerified.readValueOf(after);
    } catch (_) {
      return true;
    }
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
