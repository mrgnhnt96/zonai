import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

/// What one API token may do.
///
/// Stored on the token's `_api_tokens` row, not carried on the wire, so it is
/// server-side state that only an admin (or someone with filesystem access to
/// the database) could have written.
///
/// The scope is a **hard gate evaluated before rules run**, not an input to
/// them: a token is refused an out-of-scope `(table, operation)` pair no
/// matter how permissive that table's rule file is. Rules then run as usual
/// and may deny further. Widening is therefore only ever possible by editing
/// the row.
final class ApiTokenScope {
  const ApiTokenScope({
    required this.tables,
    required this.operations,
    this.allOperations = false,
    this.customOperations = const {},
    this.admin = true,
    bool? canEdit,
    this.rateLimit,
  }) : _canEdit = canEdit;

  factory ApiTokenScope.fromJson(Map<String, Object?> json) {
    final rawOperations = _stringSet(json['operations']);

    return ApiTokenScope(
      tables: _stringSet(json['tables']),
      operations: {
        for (final name in rawOperations)
          if (TableOperation.fromString(name) case final operation?) operation,
      },
      allOperations: rawOperations.contains(wildcard),
      customOperations: _stringSet(json['customOperations']),
      // Deliberately strict, unlike the constructor's default: the *authoring*
      // default is admin, but a decode is what an unparsable or truncated
      // `scope` column goes through, and that one must fail closed. Every row
      // this codebase writes came from [toJson], which always emits the key,
      // so the absent case is a corrupted column or a hand-written row -- and
      // a hand-written row that forgot to say `admin` is exactly the row that
      // should not silently be one.
      admin: json['admin'] == true,
      canEdit: switch (json['canEdit']) {
        final bool canEdit => canEdit,
        // Absent, so let [canEdit] derive itself rather than reading as a
        // hard `false` -- see the getter.
        _ => null,
      },
      rateLimit: switch (json['rateLimit']) {
        final Map<String, dynamic> policy => RateLimitPolicy.fromJson(policy),
        final Map<Object?, Object?> policy => RateLimitPolicy.fromJson(
          policy.map((key, value) => MapEntry('$key', value)),
        ),
        _ => null,
      },
    );
  }

  /// A token scoped to nothing. What an unparsable or absent `scope` column
  /// decodes to, so a corrupted row fails closed rather than open.
  static const none = ApiTokenScope(
    tables: {},
    operations: {},
    // Explicit, because [admin] now defaults to true. This value is what an
    // absent `scope` decodes to, and it must grant nothing at all.
    admin: false,
    canEdit: false,
  );

  /// The member of [tables] / [customOperations] meaning "every one", and the
  /// value `operations` carries on the wire when [allOperations] is set.
  ///
  /// Never the internal tables. `"*"` is a wildcard over the app's
  /// collections; `_api_tokens`, `_jwt`, `_auth_challenges` and the rest are
  /// excluded by the gate itself, unconditionally, and naming one explicitly
  /// is refused when the token is created. Otherwise `"*"` would be a route
  /// to every session id and every outstanding auth challenge in the
  /// database -- and, through `_api_tokens`, to minting a wider token.
  ///
  /// In all three positions the wildcard is **stored, not expanded**: the
  /// `_api_tokens` row keeps the literal `"*"` and the gate tests for it on
  /// each request. So a collection, a custom operation, or a built-in
  /// operation that did not exist when the token was minted is covered by it
  /// anyway. Expanding at mint would freeze the grant to whatever the product
  /// happened to offer that day, and the surprise would land months later on
  /// whoever added the seventh operation.
  static const wildcard = '*';

  /// Collection names this token may touch, or `{'*'}`.
  final Set<String> tables;

  /// Which of the six built-in operations are permitted. Ignored when
  /// [allOperations] is set, which is the wildcard's stored form.
  final Set<TableOperation> operations;

  /// Every built-in operation, including ones added after this token was
  /// minted -- what `--operations '*'` grants.
  ///
  /// A separate flag rather than a member of [operations] only because
  /// [TableOperation] is a closed enum and `"*"` is not one of its values.
  /// Semantically it is the same wildcard [tables] and [customOperations]
  /// carry, and [toJson] writes it in the same shape: `["*"]`.
  final bool allOperations;

  /// Named custom operations (`TableOperations.custom`) this token may call,
  /// or `{'*'}`.
  final Set<String> customOperations;

  /// Whether this token satisfies the *default* rule implementations, which
  /// deny everyone but an admin (`BaseTableRules`).
  ///
  /// **Defaults to true.** Not a bypass: rules still run, a rule that asks
  /// for something else still decides, and the scope gate has already refused
  /// every table and operation the token was not granted. Without it a token
  /// is inert against any collection whose rules were never overridden, which
  /// is what almost every collection is -- so a non-admin token reads as
  /// broken rather than as restricted. Narrowing is the scope's job.
  final bool admin;

  /// The write half of [admin] -- `jwt.admin.canEdit`. Implies nothing on its
  /// own; a token with `canEdit` and no `update` in [operations] still cannot
  /// update.
  ///
  /// Derived when it was not stated: an admin token granted any of
  /// [writeOperations] carries it, a read-only one does not. So a `--read`
  /// token is not handed a write grant it has no operation to spend. State it
  /// explicitly to override the derivation in either direction; [toJson]
  /// always emits the resolved answer, so a row is never ambiguous.
  bool get canEdit =>
      _canEdit ??
      (admin && (allOperations || operations.any(writeOperations.contains)));

  final bool? _canEdit;

  /// The operations [canEdit] is derived from -- the ones that write.
  static const writeOperations = {
    TableOperation.create,
    TableOperation.update,
    TableOperation.delete,
  };

  /// Requests per window for this token, bucketed on the token rather than
  /// the client IP. Null means the collection's own policy applies.
  final RateLimitPolicy? rateLimit;

  /// The stricter of this scope's admin grant and [table]'s own, for a token
  /// **bound** to an auth row.
  ///
  /// An unbound token has no table to derive from -- its powers come from a
  /// `_api_tokens` row only an admin could have written, and that is the
  /// safety property. A bound one does have a table, and must never be more
  /// privileged than the row it acts as: a personal access token for an
  /// ordinary user is not an admin key, whatever its row says. Applied at
  /// resolution rather than at mint, so removing `AsAdmin` from a collection
  /// demotes every outstanding token for it on the next request -- the same
  /// property `_withServerDerivedAdmin` gives a signed JWT.
  ApiTokenScope clampedTo(({bool isAdmin, bool canEdit}) table) {
    final grantedAdmin = admin && table.isAdmin;
    final grantedCanEdit = grantedAdmin && canEdit && table.canEdit;
    if (grantedAdmin == admin && grantedCanEdit == canEdit) return this;

    return ApiTokenScope(
      tables: tables,
      operations: operations,
      allOperations: allOperations,
      customOperations: customOperations,
      admin: grantedAdmin,
      canEdit: grantedCanEdit,
      rateLimit: rateLimit,
    );
  }

  bool allowsTable(String table) =>
      tables.contains(wildcard) || tables.contains(table);

  bool allowsOperation(TableOperation operation) =>
      allOperations || operations.contains(operation);

  bool allowsCustomOperation(String operation) =>
      customOperations.contains(wildcard) ||
      customOperations.contains(operation);

  /// Whether this scope grants no operation at all -- the token that may
  /// reach a table and do nothing on it.
  bool get grantsNoOperation =>
      !allOperations && operations.isEmpty && customOperations.isEmpty;

  Map<String, Object?> toJson() => {
    'tables': tables.toList()..sort(),
    'operations': _operationsJson,
    'customOperations': customOperations.toList()..sort(),
    'admin': admin,
    'canEdit': canEdit,
    'rateLimit': rateLimit?.toJson(),
  };

  /// The wildcard replaces the list rather than joining it: it already
  /// subsumes every member, and a row reading `["*", "view"]` invites the
  /// reader to wonder which half won.
  ///
  /// Written as a getter rather than inline in [toJson] because `..sort()`
  /// binds looser than `? :` -- a conditional there would have cascaded onto
  /// the const wildcard list instead of onto the names.
  List<String> get _operationsJson {
    if (allOperations) return const [wildcard];
    return [for (final operation in operations) operation.name]..sort();
  }

  static Set<String> _stringSet(Object? raw) => switch (raw) {
    final List<Object?> list => {
      for (final entry in list)
        if (entry is String) entry,
    },
    // Tolerated on the way in only: `"tables": "*"` is the shape a human
    // writes by hand, and refusing it would fail closed on a row that is
    // obviously trying to say something. `toJson` always emits a list.
    final String single => {single},
    _ => const {},
  };
}
