/// The sign-up request [AuthExtension.beforeSignUp] gets to refuse.
///
/// ## Why this is not a typed row
///
/// Every other extension hook receives `R` — the app's own row class — and
/// `beforeSignUp` was written that way first. It does not work, and the
/// reason is structural rather than a bug that could be fixed:
///
/// The row does not exist yet. Building one means `table.safeCreate` inventing
/// a value for every column the sign-up body did not supply, and `safeCreate`
/// only knows how to invent for five transformers (created-at, updated-at,
/// generated primary key, secret, server-generated). A non-nullable column
/// outside that set — `is_verified` is one, on every `AuthTable` — stays
/// absent, and `decode(null)` throws inside the extension worker. The e2e
/// caught exactly that: an ordinary password sign-up died with `type 'Null'
/// is not a subtype of type 'bool'` before the hook was ever entered.
///
/// Widening `safeCreate` would move the failure rather than remove it. A
/// column whose transformer rejects a fabricated zero — an enum, a checked
/// string — would still throw, and it would throw in production, inside the
/// hook an app wrote to *protect* its sign-up. A gate that crashes on some
/// table shapes is worse than one that is honest about what it knows.
///
/// So this carries what actually exists at that moment, and nothing else.
final class SignUpCandidate {
  const SignUpCandidate({
    required this.table,
    required this.email,
    required this.object,
  });

  /// The auth collection being signed up into.
  final String table;

  /// The address the sign-up was made with.
  ///
  /// The *value*, not the column — an auth table names its email column
  /// itself, and the sign-up payload carries the address separately from
  /// [object] all the way down.
  final String email;

  /// The extra columns the sign-up body carried, exactly as the client sent
  /// them. Empty when it sent none.
  ///
  /// Unvalidated and unsanitized: rules and the insert have not run yet, which
  /// is the whole point of being here. Do not trust a value in here to be the
  /// value the row would end up with.
  final Map<String, Object?> object;

  /// The value the sign-up body carried for [column], or `null` if it carried
  /// none. Shorthand for `object[column]`.
  Object? operator [](String column) => object[column];

  @override
  String toString() =>
      'SignUpCandidate(table: $table, email: $email, object: $object)';
}
