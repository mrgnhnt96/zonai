import 'package:zonai_schema/zonai_schema.dart';

/// One `(table, user_id)` marker — "this account must choose a new password
/// before a password sign-in will mint a session for it". Set out of band by
/// an operator, read on the password sign-in path, deleted when the password
/// actually changes; see `docs/force-password-reset-design.md` §3.
///
/// Durable on purpose. The reset *ticket* a gated sign-in hands back is an
/// ordinary `_auth_challenges` row with its own short expiry — this row is the
/// requirement, and it has to outlive every ticket issued against it. A
/// requirement that expired on its own would silently restore the old
/// password, which is the failure the feature exists to prevent (design §1).
class PasswordResetRequirement {
  PasswordResetRequirement({
    required this.id,
    required this.table,
    required this.userId,
    required this.reason,
    required this.createdBy,
  }) : createdAt = .now();

  PasswordResetRequirement._({
    required this.id,
    required this.table,
    required this.userId,
    required this.reason,
    required this.createdBy,
    required this.createdAt,
  });

  final PasswordResetRequirementId id;

  /// The auth collection's name, e.g. `'users'`.
  final String table;

  /// The `table` row this requirement constrains. Not a database foreign key
  /// — `table` names an app-defined schema, so the reference is virtual, the
  /// same shape and the same gap as `_jwt.user_id` and `_oauth_identities`.
  final Id userId;

  /// Why it was set. Carried to the client in the 403's `details.reason` so a
  /// sign-in screen can say something truer than "you must reset".
  final PasswordResetReason reason;

  /// The admin row id that set it, or `'cli'` when it came from the server
  /// box. Nullable — a requirement synthesized by policy has no author.
  final String? createdBy;

  final DateTime createdAt;
}

/// Why an account is being made to choose a new password.
///
/// This crosses the wire in the 403 envelope, so the names are API: renaming
/// one breaks a client branching on it.
enum PasswordResetReason {
  /// An operator set it deliberately, with no stronger statement implied.
  adminForced,

  /// The current password was chosen by somebody other than the account
  /// holder — `zonai db admin reset-password`, or `admin add --password`.
  temporaryPassword,

  /// The password is believed to be known to someone else.
  compromised,

  /// Synthesized by a password-age or rotation policy rather than by a person.
  passwordPolicy,
}

class PasswordResetRequirementId implements Id {
  PasswordResetRequirementId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  static PasswordResetRequirementId generate() =>
      PasswordResetRequirementId(Id.generate(_suffix));

  static const _suffix = 'pwr';

  @override
  final String value;
}

class PasswordResetRequirementTable extends Table<PasswordResetRequirement> {
  PasswordResetRequirementTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PasswordResetRequirementId.new,
        generate: PasswordResetRequirementId.generate,
      ),
      table = $.text('table', (s) => s.table),
      userId = $.id<UnknownId, UnknownId>(
        'user_id',
        (s) => UnknownId(s.userId.value),
        fromString: UnknownId.new,
        generate: () => throw Exception(
          'User ID should not be generated for password reset requirements',
        ),
        isPrimaryKey: false,
        synthetic: const UnknownId('__password_reset_requirement__'),
      ),
      reason = $.enumerator(
        'reason',
        PasswordResetReason.values,
        (s) => s.reason,
      ),
      createdBy = $.text('created_by', (s) => s.createdBy),
      createdAt = $.createdAt('created_at', (s) => s.createdAt);

  final IdColumn<PasswordResetRequirementId> id;
  final TextColumn table;
  final IdColumn<UnknownId> userId;
  final EnumColumn<PasswordResetReason> reason;
  final ColumnType<String?> createdBy;
  final DateTimeColumn createdAt;

  @override
  PasswordResetRequirement fromRow(RowReader read) {
    return PasswordResetRequirement._(
      id: read(id),
      table: read(table),
      userId: read(userId),
      reason: read(reason),
      createdBy: read(createdBy),
      createdAt: read(createdAt),
    );
  }
}

// The unique index is the idempotency guarantee, not an optimisation: setting
// a requirement twice on the same account must leave one row, so the mutator
// can INSERT OR REPLACE and never accumulate duplicates that a later DELETE
// would only half-clear. It doubles as the sign-in lookup index — that read
// sits on the password path and is keyed on exactly these two columns.
//
// No cascade on user deletion, for the reason `_oauth_identities` gives at
// length: `user_id` names a row in an app-defined table chosen per collection,
// which this layer cannot express as a real foreign key. A deleted user leaves
// an orphaned requirement, exactly as it already leaves orphaned JWTs.
final passwordResetRequirements = table(
  '_password_reset_requirements',
  PasswordResetRequirementTable.new,
  (table) {
    uniqueIndex(
      'password_reset_requirement_account_unique',
    ).on(table.table, table.userId);
  },
);
