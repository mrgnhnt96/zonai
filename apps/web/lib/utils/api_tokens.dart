/// The `GET /admin/tokens` payload, and the decisions the API Tokens screen
/// makes about it (`docs/api-tokens-design.md` §8).
///
/// Pure on purpose, for the reason `admin_members.dart` is: the interesting
/// parts here are *statuses* — live, revoked, expired — and a UI that merely
/// looks like it labels a row correctly is indistinguishable from one that
/// labels it wrongly. All of it is falsifiable without a browser or a server.
library;

/// What a token's row says about whether it still works.
///
/// Three states and not two: `revoked` and `expired` both mean "stopped
/// working", and collapsing them loses the only thing anyone wants to know
/// when an integration breaks at 3am — whether somebody withdrew it or it
/// simply ran out.
enum ApiTokenStatus {
  live('Live'),
  expired('Expired'),
  revoked('Revoked');

  const ApiTokenStatus(this.label);

  final String label;
}

/// One `_api_tokens` row as the dashboard sees it.
///
/// There is no field for the credential itself, here or on the server: the row
/// keeps `sha256(plaintext)` and `buildTokenBody` does not send even that. The
/// plaintext exists exactly once, in the response to the mint that created it.
final class ApiTokenRow {
  const ApiTokenRow({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.scope,
    required this.createdAt,
    this.claims = const {},
    this.boundTable,
    this.boundUserId,
    this.createdBy,
    this.expiresAt,
    this.revokedAt,
    this.lastUsedAt,
  });

  final String id;
  final String name;

  /// The plaintext's first characters, so a token in a log line can be matched
  /// to a row without the server storing anything that opens it.
  final String tokenPrefix;

  final ApiTokenScopeView scope;
  final Map<String, Object?> claims;
  final String? boundTable;
  final String? boundUserId;
  final String? createdBy;
  final DateTime createdAt;

  /// Null means **never**, which is the whole point of the feature — so it has
  /// to survive as null rather than as an epoch. "Expires never" and "expired
  /// in 1970" are opposite answers.
  final DateTime? expiresAt;

  final DateTime? revokedAt;

  /// Written lazily by the server: "used this hour" versus "not since March"
  /// is the whole decision it supports.
  final DateTime? lastUsedAt;

  bool get isRevoked => revokedAt != null;

  bool isExpiredAt(DateTime now) => switch (expiresAt) {
    final at? => now.isAfter(at),
    null => false,
  };

  /// Revoked beats expired: a token somebody withdrew is withdrawn whether or
  /// not its expiry has also passed, and the reverse reading would credit the
  /// clock for a decision a person made.
  ApiTokenStatus statusAt(DateTime now) {
    if (isRevoked) return ApiTokenStatus.revoked;
    if (isExpiredAt(now)) return ApiTokenStatus.expired;
    return ApiTokenStatus.live;
  }

  bool get isBound => boundTable != null && boundUserId != null;
}

/// The scope column, read for display.
///
/// Deliberately does not re-derive anything. `canEdit` is resolved on the
/// server before it is written, and re-deriving it here would let the screen
/// and the row disagree the day the derivation changes.
final class ApiTokenScopeView {
  const ApiTokenScopeView({
    required this.tables,
    required this.operations,
    required this.customOperations,
    required this.admin,
    required this.canEdit,
  });

  static const empty = ApiTokenScopeView(
    tables: [],
    operations: [],
    customOperations: [],
    admin: false,
    canEdit: false,
  );

  final List<String> tables;
  final List<String> operations;
  final List<String> customOperations;
  final bool admin;
  final bool canEdit;

  bool get isWildcard => tables.contains('*');
}

/// Parses the `data` object of `GET /admin/tokens`.
///
/// Tolerant the same way `parseAdminMembers` is: a row this cannot read is
/// skipped rather than thrown on, because one malformed row must not cost the
/// operator the list they came to revoke something from.
List<ApiTokenRow> parseApiTokens(Map<String, Object?> data) {
  final rows = <ApiTokenRow>[];
  if (data['tokens'] case final List raw) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;

      rows.add(
        ApiTokenRow(
          id: id,
          name: entry['name'] is String ? entry['name'] as String : id,
          tokenPrefix: entry['tokenPrefix'] is String ? entry['tokenPrefix'] as String : '',
          scope: parseApiTokenScope(entry['scope']),
          claims: switch (entry['claims']) {
            final Map raw => {for (final MapEntry(:key, :value) in raw.entries) '$key': value as Object?},
            _ => const {},
          },
          boundTable: entry['boundTable'] is String ? entry['boundTable'] as String : null,
          boundUserId: entry['boundUserId'] is String ? entry['boundUserId'] as String : null,
          createdBy: entry['createdBy'] is String ? entry['createdBy'] as String : null,
          createdAt: _parseTimestamp(entry['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          expiresAt: _parseTimestamp(entry['expiresAt']),
          revokedAt: _parseTimestamp(entry['revokedAt']),
          lastUsedAt: _parseTimestamp(entry['lastUsedAt']),
        ),
      );
    }
  }

  // Newest first: the token someone just minted is the one they are looking
  // for, and it is the one a fresh page load exists to show them.
  rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return rows;
}

ApiTokenScopeView parseApiTokenScope(Object? raw) {
  if (raw is! Map) return ApiTokenScopeView.empty;

  return ApiTokenScopeView(
    tables: _stringList(raw['tables']),
    operations: _stringList(raw['operations']),
    customOperations: _stringList(raw['customOperations']),
    admin: raw['admin'] == true,
    canEdit: raw['canEdit'] == true,
  );
}

/// What the scope column says, in one line for a table cell.
///
/// `"*"` is spelled out rather than shown as a bare asterisk: an operator
/// scanning a list for the credential with too much reach should not have to
/// know that one glyph is the wide one.
String describeScope(ApiTokenScopeView scope) {
  final tables = scope.isWildcard
      ? 'every collection'
      : switch (scope.tables.length) {
          0 => 'no collections',
          1 => scope.tables.single,
          _ => scope.tables.join(', '),
        };

  final operations = [...scope.operations, ...scope.customOperations];

  return '$tables · ${operations.isEmpty ? 'nothing' : operations.join(', ')}';
}

/// The six built-in operations, in the order the form offers them: the three
/// reads, then the three writes.
///
/// Not `TableOperation.values` — that enum's declaration order puts the writes
/// first, and a form whose first three checkboxes are `create`, `update`,
/// `delete` invites a wider token than the person meant.
const apiTokenOperations = ['view', 'list', 'count', 'create', 'update', 'delete'];

/// The write half, and the reason [ApiTokenDraft.canEdit] is left unsent.
const apiTokenWriteOperations = {'create', 'update', 'delete'};

/// How long a token lasts, as the form offers it.
///
/// `never` is first and is the default, because it is the point of the
/// feature: revocation, not expiry, is what makes a permanent credential safe,
/// and burying it under a list of durations argues the opposite.
enum ApiTokenExpiry {
  never('Never', null),
  days30('30 days', Duration(days: 30)),
  days90('90 days', Duration(days: 90)),
  year('1 year', Duration(days: 365));

  const ApiTokenExpiry(this.label, this.duration);

  final String label;
  final Duration? duration;

  static ApiTokenExpiry fromName(String name) => values.where((value) => value.name == name).firstOrNull ?? never;
}

/// What the mint form currently holds.
///
/// A value type rather than a bag of `setState` fields so the two things worth
/// pinning — what gets sent, and when the button is allowed to be pressed —
/// are falsifiable without rendering anything.
final class ApiTokenDraft {
  const ApiTokenDraft({
    this.name = '',
    this.tables = '',
    this.operations = const {'view', 'list', 'count'},
    this.admin = true,
    this.expiry = ApiTokenExpiry.never,
  });

  final String name;

  /// Comma-separated, or `*`. Free text rather than a picker because the
  /// wildcard and a not-yet-created collection both have to be expressible,
  /// and a picker of existing tables can express neither.
  final String tables;

  final Set<String> operations;

  /// Defaults to true, matching `zonai db token create`. A non-admin token is
  /// denied by the DEFAULT rules, so it reads as broken rather than as narrow.
  final bool admin;

  final ApiTokenExpiry expiry;

  ApiTokenDraft copyWith({String? name, String? tables, Set<String>? operations, bool? admin, ApiTokenExpiry? expiry}) {
    return ApiTokenDraft(
      name: name ?? this.name,
      tables: tables ?? this.tables,
      operations: operations ?? this.operations,
      admin: admin ?? this.admin,
      expiry: expiry ?? this.expiry,
    );
  }

  List<String> get tableList => [
    for (final part in tables.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// Why this cannot be minted yet, in words — or `null` when it can.
  ///
  /// Said on the disabled button rather than raised after the click, the same
  /// way the Admins screen states its refusals: these are not errors, they are
  /// the form not being finished, and a button that fails when pressed teaches
  /// nothing until after it has been pressed.
  String? get refusal {
    if (name.trim().isEmpty) {
      return 'Give it a name. An unnamed credential is one nobody ever '
          'revokes, because nobody can tell what would break.';
    }
    if (tableList.isEmpty) {
      return 'Name at least one collection, or "*" for every one.';
    }
    if (operations.isEmpty) {
      return 'Choose at least one operation. A token that may reach a '
          'collection but do nothing to it can do nothing at all.';
    }
    return null;
  }

  /// The `POST /admin/tokens` body.
  ///
  /// `canEdit` is deliberately absent: the server derives it from the granted
  /// operations, and a screen that sent its own answer would have to be kept
  /// in step with a rule it does not own.
  Map<String, Object?> toRequestBody({required DateTime now}) {
    return {
      'name': name.trim(),
      'tables': tableList,
      'operations': [
        for (final operation in apiTokenOperations)
          if (operations.contains(operation)) operation,
      ],
      'admin': admin,
      'expiresAt': switch (expiry.duration) {
        final duration? => now.toUtc().add(duration).toIso8601String(),
        null => null,
      },
    };
  }
}

/// When it was made, when it was last used, and when it stops — in one line.
///
/// "Never used" is stated rather than left blank: a token nobody has ever
/// presented is the one it is safe to delete, and that is exactly the question
/// somebody opens this screen to answer.
String describeTokenTimeline(ApiTokenRow row, {required DateTime now}) {
  final parts = <String>['Created ${_relative(row.createdAt, now)}'];

  parts.add(switch (row.lastUsedAt) {
    final at? => 'last used ${_relative(at, now)}',
    null => 'never used',
  });

  if (row.revokedAt case final at?) {
    parts.add('revoked ${_relative(at, now)}');
  } else if (row.expiresAt case final at?) {
    parts.add(now.isAfter(at) ? 'expired ${_relative(at, now)}' : 'expires ${_relative(at, now)}');
  } else {
    parts.add('never expires');
  }

  return parts.join(' · ');
}

/// A coarse, tenseless age. Coarse on purpose: the decisions this screen
/// supports are "this hour" versus "not since March", and a precise duration
/// would imply the `last_used_at` column carries a precision it deliberately
/// does not (the server throttles that write).
String _relative(DateTime at, DateTime now) {
  final delta = at.difference(now);
  final ahead = !delta.isNegative;
  final magnitude = delta.abs();

  final amount = switch (magnitude) {
    final d when d.inMinutes < 1 => 'just now',
    final d when d.inMinutes < 60 => '${d.inMinutes}m',
    final d when d.inHours < 24 => '${d.inHours}h',
    final d when d.inDays < 30 => '${d.inDays}d',
    final d when d.inDays < 365 => '${d.inDays ~/ 30}mo',
    final d => '${d.inDays ~/ 365}y',
  };

  if (amount == 'just now') return amount;
  return ahead ? 'in $amount' : '$amount ago';
}

/// Why a token cannot be revoked, in words — or `null` when it can.
///
/// Only one reason exists, and it is not an error: a revoked token is already
/// revoked. Saying so on a disabled control beats letting somebody click into
/// a no-op and wonder whether it worked.
String? revokeRefusal(ApiTokenRow row) {
  if (row.isRevoked) {
    return 'Already revoked. Delete it to remove the record as well.';
  }
  return null;
}

List<String> _stringList(Object? raw) => switch (raw) {
  final List list => [
    for (final entry in list)
      if (entry is String) entry,
  ],
  final String single => [single],
  _ => const [],
};

DateTime? _parseTimestamp(Object? raw) => switch (raw) {
  final String value => DateTime.tryParse(value)?.toLocal(),
  final num millis => DateTime.fromMillisecondsSinceEpoch(millis.toInt()).toLocal(),
  _ => null,
};
