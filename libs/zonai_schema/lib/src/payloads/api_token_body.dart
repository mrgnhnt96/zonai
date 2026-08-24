import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/src/types/api_token_scope.dart';

/// The `POST /admin/tokens` body — everything `zonai db token create` takes,
/// in the shape the dashboard sends it.
///
/// Validated here rather than in the handler because a scope that could not
/// have been meant is a token someone believes works, and they will find out
/// when their integration is already deployed. The deeper refusals (an
/// internal table, `canEdit` without `admin`, a binding that names no row)
/// belong to `ZonaiDb.createApiToken` and are not repeated: two copies of a
/// rule is one copy too many, and the CLI reaches only that one.
class ApiTokenCreateBody {
  const ApiTokenCreateBody({
    required this.name,
    required this.scope,
    this.claims = const {},
    this.boundTable,
    this.boundUserId,
    this.expiresAt,
  });

  factory ApiTokenCreateBody.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw ArgumentError.value(
        json['name'],
        'name',
        'POST /admin/tokens requires a non-empty "name" -- an unnamed '
            'credential is one nobody ever revokes, because nobody can tell '
            'what would break',
      );
    }

    final operations = <TableOperation>{};
    for (final raw in _stringList(json['operations'], 'operations')) {
      final operation = TableOperation.fromString(raw);
      if (operation == null) {
        throw ArgumentError.value(
          raw,
          'operations',
          'unknown operation -- expected one of: '
              '${TableOperation.values.map((o) => o.name).join(', ')}',
        );
      }
      operations.add(operation);
    }

    final (boundTable, boundUserId) = (
      json['boundTable'] as String?,
      json['boundUserId'] as String?,
    );
    if ((boundTable == null) != (boundUserId == null)) {
      throw ArgumentError.value(
        boundTable ?? boundUserId,
        'boundTable/boundUserId',
        'bind a token to both a table and a row id, or to neither',
      );
    }

    return ApiTokenCreateBody(
      name: name.trim(),
      scope: ApiTokenScope(
        tables: _stringList(json['tables'], 'tables').toSet(),
        operations: operations,
        customOperations: _stringList(
          json['customOperations'],
          'customOperations',
        ).toSet(),
        // Absent means admin: a token that is not one is denied by the DEFAULT
        // rules, so it reads as broken rather than as narrow. Sending
        // `"admin": false` is how the dashboard asks for the other thing.
        admin: json['admin'] != false,
        // Absent means DERIVED -- on for an admin token granted a write
        // operation, off for a read-only one. A hard `false` here would hand
        // every `--write` token a scope it cannot spend.
        canEdit: json['canEdit'] as bool?,
      ),
      claims: switch (json['claims']) {
        final Map<Object?, Object?> claims => claims.map(
          (key, value) => MapEntry('$key', value),
        ),
        _ => const {},
      },
      boundTable: boundTable,
      boundUserId: boundUserId,
      expiresAt: switch (json['expiresAt']) {
        null => null,
        final String raw when raw.trim().isEmpty => null,
        final String raw =>
          DateTime.tryParse(raw) ??
              (throw ArgumentError.value(
                raw,
                'expiresAt',
                'expected an ISO-8601 timestamp, or null for never',
              )),
        final value => throw ArgumentError.value(
          value,
          'expiresAt',
          'expected an ISO-8601 timestamp, or null for never',
        ),
      },
    );
  }

  final String name;
  final ApiTokenScope scope;
  final Map<String, dynamic> claims;
  final String? boundTable;
  final String? boundUserId;

  /// Null means **never**, which is the point of the feature.
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    ...scope.toJson(),
    'claims': claims,
    'boundTable': boundTable,
    'boundUserId': boundUserId,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  static List<String> _stringList(Object? raw, String field) {
    return switch (raw) {
      null => const [],
      // Tolerated for the same reason `ApiTokenScope.fromJson` tolerates it:
      // `"tables": "*"` is what a human writes by hand.
      final String single when single.trim().isNotEmpty => [single.trim()],
      final String _ => const [],
      final List<Object?> list => [
        for (final entry in list)
          if (entry is String && entry.trim().isNotEmpty) entry.trim(),
      ],
      _ => throw ArgumentError.value(raw, field, 'expected a list of strings'),
    };
  }
}
