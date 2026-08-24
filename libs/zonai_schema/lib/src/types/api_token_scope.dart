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
    this.customOperations = const {},
    this.admin = false,
    this.canEdit = false,
    this.rateLimit,
  });

  factory ApiTokenScope.fromJson(Map<String, Object?> json) {
    return ApiTokenScope(
      tables: _stringSet(json['tables']),
      operations: {
        for (final name in _stringSet(json['operations']))
          if (TableOperation.fromString(name) case final operation?) operation,
      },
      customOperations: _stringSet(json['customOperations']),
      admin: json['admin'] == true,
      canEdit: json['canEdit'] == true,
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
  static const none = ApiTokenScope(tables: {}, operations: {});

  /// The member of [tables] / [customOperations] meaning "every one".
  ///
  /// Never the internal tables. `"*"` is a wildcard over the app's
  /// collections; `_api_tokens`, `_jwt`, `_auth_challenges` and the rest are
  /// excluded by the gate itself, unconditionally, and naming one explicitly
  /// is refused when the token is created. Otherwise `"*"` would be a route
  /// to every session id and every outstanding auth challenge in the
  /// database -- and, through `_api_tokens`, to minting a wider token.
  static const wildcard = '*';

  /// Collection names this token may touch, or `{'*'}`.
  final Set<String> tables;

  /// Which of the six built-in operations are permitted.
  final Set<TableOperation> operations;

  /// Named custom operations (`TableOperations.custom`) this token may call,
  /// or `{'*'}`.
  final Set<String> customOperations;

  /// Whether this token satisfies the *default* rule implementations, which
  /// deny everyone but an admin (`BaseTableRules`).
  ///
  /// Not a bypass: rules still run, and a rule that asks for something else
  /// still decides. Without it a token is inert against any collection whose
  /// rules were never overridden.
  final bool admin;

  /// The write half of [admin] -- `jwt.admin.canEdit`. Implies nothing on its
  /// own; a token with `canEdit` and no `update` in [operations] still cannot
  /// update.
  final bool canEdit;

  /// Requests per window for this token, bucketed on the token rather than
  /// the client IP. Null means the collection's own policy applies.
  final RateLimitPolicy? rateLimit;

  bool allowsTable(String table) =>
      tables.contains(wildcard) || tables.contains(table);

  bool allowsOperation(TableOperation operation) =>
      operations.contains(operation);

  bool allowsCustomOperation(String operation) =>
      customOperations.contains(wildcard) ||
      customOperations.contains(operation);

  Map<String, Object?> toJson() => {
    'tables': tables.toList()..sort(),
    'operations': [for (final operation in operations) operation.name]..sort(),
    'customOperations': customOperations.toList()..sort(),
    'admin': admin,
    'canEdit': canEdit,
    'rateLimit': rateLimit?.toJson(),
  };

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
