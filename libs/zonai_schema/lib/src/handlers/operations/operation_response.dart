import 'dart:convert';

import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';
import 'package:zonai_schema/src/types/oauth/oauth_brand.dart';
import 'package:zonai_schema/src/types/oauth/oauth_claim_map.dart';
import 'package:zonai_schema/src/types/oauth/oauth_endpoints.dart';
import 'package:zonai_schema/src/types/oauth/oauth_linking.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_kind.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_public.dart';
import 'package:zonai_schema/src/types/schema_shape.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';
import 'package:zonai_schema/src/update/update.dart';

sealed class OperationResponse extends Response {
  const OperationResponse({
    required super.path,
    required super.id,
    required super.payload,
  });

  factory OperationResponse.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid operation response path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid operation response id: ${json['id']}');
    }

    return switch (path) {
      PerformOperationResponse._path => PerformOperationResponse.fromJson(json),
      ColumnNameResponse._path => ColumnNameResponse.fromJson(json),
      ColumnReferenceResponse._path => ColumnReferenceResponse.fromJson(json),
      AllTableSchemaShapesResponse._path =>
        AllTableSchemaShapesResponse.fromJson(json),
      JwtConfigResponse._path => JwtConfigResponse.fromJson(json),
      SanitizeOperationResponse._path => SanitizeOperationResponse.fromJson(
        json,
      ),
      AdminTablesResponse._path => AdminTablesResponse.fromJson(json),
      OAuthProvidersResponse._path => OAuthProvidersResponse.fromJson(json),
      OAuthProviderConfigResponse._path => OAuthProviderConfigResponse.fromJson(
        json,
      ),
      MagicLinkConfigResponse._path => MagicLinkConfigResponse.fromJson(json),
      ResetPasswordConfigResponse._path => ResetPasswordConfigResponse.fromJson(
        json,
      ),
      VerifyEmailConfigResponse._path => VerifyEmailConfigResponse.fromJson(
        json,
      ),
      _ => throw ArgumentError('Invalid operation response path: $path'),
    };
  }
}

final class ColumnNameResponse extends OperationResponse {
  const ColumnNameResponse({
    required super.id,
    required this.name,
    required this.column,
  }) : super(path: _path, payload: const {});

  factory ColumnNameResponse.fromJson(Map<String, dynamic> json) {
    return ColumnNameResponse(
      id: json['id'] as String,
      name: json['name'] as String?,
      column: ColumnName.values.byName(json['column'] as String),
    );
  }

  static const _path = '${Response.prefix}.operation.get_column_name';

  final String? name;
  final ColumnName column;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'name': name, 'column': column.name};
  }
}

final class ColumnReferenceResponse extends OperationResponse {
  const ColumnReferenceResponse({
    required super.id,
    required this.columnName,
    this.referencedTable,
    this.referencedColumn,
  }) : super(path: _path, payload: const {});

  factory ColumnReferenceResponse.fromJson(Map<String, dynamic> json) {
    return ColumnReferenceResponse(
      id: json['id'] as String,
      columnName: json['columnName'] as String,
      referencedTable: json['referencedTable'] as String?,
      referencedColumn: json['referencedColumn'] as String?,
    );
  }

  static const _path = '${Response.prefix}.operation.get_column_reference';

  final String columnName;
  final String? referencedTable;
  final String? referencedColumn;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'columnName': columnName,
      'referencedTable': referencedTable,
      'referencedColumn': referencedColumn,
    };
  }
}

final class AllTableSchemaShapesResponse extends OperationResponse {
  const AllTableSchemaShapesResponse({required super.id, required this.shapes})
    : super(path: _path, payload: const {});

  factory AllTableSchemaShapesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['shapes'] as Map;
    return AllTableSchemaShapesResponse(
      id: json['id'] as String,
      shapes: {
        for (final MapEntry(:key, :value) in raw.entries)
          key as String: TableSchemaShape.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
      },
    );
  }

  static const _path =
      '${Response.prefix}.operation.get_all_table_schema_shapes';

  final Map<String, TableSchemaShape> shapes;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'shapes': {for (final e in shapes.entries) e.key: e.value.toJson()},
  };
}

final class PerformOperationResponse extends OperationResponse {
  const PerformOperationResponse({
    required super.id,
    required this.query,
    this.values = const [],
    this.updates = const [],
  }) : super(path: _path, payload: const {});

  factory PerformOperationResponse.fromJson(Map<String, dynamic> json) {
    return PerformOperationResponse(
      id: json['id'] as String,
      query: json['query'] as String,
      values: switch (json['values']) {
        final List<dynamic> v => List<Object?>.from(v),
        _ => const [],
      },
      updates: switch (json['updates']) {
        final List<dynamic> v => [
          for (final update in v)
            Update.fromJson(update as Map<String, dynamic>),
        ],
        _ => const [],
      },
    );
  }

  static const _path = '${Response.prefix}.operation.perform';

  final String query;
  final List<Object?> values;

  /// What [query] will write, for the row rule that has to authorize it —
  /// `TableOperations.customUpdates`, which only a custom operation overrides.
  ///
  /// Empty for every built-in operation: their updates travel on the request
  /// itself, and the rule check already has them. This exists because a custom
  /// operation's writes are the server's own, so the rules half would otherwise
  /// be adjudicating the caller's proposal instead of the resulting row.
  ///
  /// These are simulated, never executed. [query] is still the only thing that
  /// writes.
  final List<Update> updates;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'query': query,
      'values': values,
      if (updates.isNotEmpty)
        'updates': [for (final update in updates) update.toJson()],
    };
  }

  @override
  String toString() {
    return '''PerformOperationResponse:
${const JsonEncoder.withIndent('  ').convert(toJson())}
''';
  }
}

final class JwtConfigResponse extends OperationResponse {
  const JwtConfigResponse({required super.id, required this.config})
    : super(path: _path, payload: const {});

  factory JwtConfigResponse.fromJson(Map<String, dynamic> json) {
    return JwtConfigResponse(
      id: json['id'] as String,
      config: JwtConfig.fromJson(json['config'] as Map<String, dynamic>),
    );
  }

  static const _path = '${Response.prefix}.auth.get_jwt_config';

  final JwtConfig config;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'config': config.toJson()};
  }
}

final class SanitizeOperationResponse extends OperationResponse {
  SanitizeOperationResponse({
    required super.id,
    required List<Map<String, dynamic>> objects,
    List<String> photoColumns = const [],
    List<String> secretColumns = const [],
  }) : objects = List.unmodifiable(objects),
       photoColumns = List.unmodifiable(photoColumns),
       secretColumns = List.unmodifiable(secretColumns),
       super(path: _path, payload: const {});

  factory SanitizeOperationResponse.fromJson(Map<String, dynamic> json) {
    return SanitizeOperationResponse(
      id: json['id'] as String,
      objects: [
        for (final e in json['objects'] as List<dynamic>)
          Map<String, dynamic>.from(e),
      ],
      photoColumns: [
        for (final column in json['photoColumns'] as List<dynamic>? ?? const [])
          column as String,
      ],
      secretColumns: [
        for (final column
            in json['secretColumns'] as List<dynamic>? ?? const [])
          column as String,
      ],
    );
  }

  static const _path = '${Response.prefix}.operation.sanitize';

  final List<Map<String, dynamic>> objects;
  final List<String> photoColumns;

  /// Secret column names for this table — host caches these to sanitize
  /// subsequent responses in-process without another ops IPC hop.
  final List<String> secretColumns;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'objects': jsonDecode(jsonEncode(objects)),
      'photoColumns': photoColumns,
      'secretColumns': secretColumns,
    };
  }
}

final class AdminTablesResponse extends OperationResponse {
  const AdminTablesResponse({required super.id, required this.tables})
    : super(path: _path, payload: const {});

  factory AdminTablesResponse.fromJson(Map<String, dynamic> json) {
    return AdminTablesResponse(
      id: json['id'] as String,
      tables: [
        for (final e in json['tables'] as List<dynamic>)
          (
            e['table'] as String,
            [
              for (final authType in e['authTypes'] as List<dynamic>)
                AuthType.values.byName(authType as String),
            ],
          ),
      ],
    );
  }

  static const _path = '${Response.prefix}.auth.get_admin_tables';

  final List<(String, List<AuthType>)> tables;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'tables': tables
          .map(
            (e) => {
              'table': e.$1,
              'authTypes': e.$2.map((e) => e.name).toList(),
            },
          )
          .toList(),
    };
  }
}

/// Reply to [GetOAuthProvidersOperationRequest]: every `(table,
/// OAuthProviderPublic)` pair across every OAuth-enabled table, already
/// redacted via [OAuthProvider.toPublic] — this is the shape the dashboard
/// and Dart client see.
final class OAuthProvidersResponse extends OperationResponse {
  const OAuthProvidersResponse({required super.id, required this.providers})
    : super(path: _path, payload: const {});

  factory OAuthProvidersResponse.fromJson(Map<String, dynamic> json) {
    return OAuthProvidersResponse(
      id: json['id'] as String,
      providers: [
        for (final p in json['providers'] as List<dynamic>)
          OAuthProviderPublic.fromJson(p as Map<String, dynamic>),
      ],
    );
  }

  static const _path = '${Response.prefix}.auth.get_oauth_providers';

  final List<OAuthProviderPublic> providers;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'providers': providers.map((p) => p.toJson()).toList(),
    };
  }
}

/// Reply to [GetOAuthProviderConfigRequest]: the full, unredacted
/// configuration for one provider — client secret / Apple signing key
/// included — or [provider] null when [GetOAuthProviderConfigRequest.table]
/// doesn't mix in `OAuth` or has no provider matching
/// [GetOAuthProviderConfigRequest.providerId].
///
/// Never routed anywhere the dashboard or Dart client can see it; only
/// `ZonaiDb`'s OAuth flow (`parts/auth/oauth.dart`) dispatches this request.
final class OAuthProviderConfigResponse extends OperationResponse {
  const OAuthProviderConfigResponse({required super.id, required this.provider})
    : super(path: _path, payload: const {});

  factory OAuthProviderConfigResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['provider'] as Map<String, dynamic>?;
    return OAuthProviderConfigResponse(
      id: json['id'] as String,
      provider: raw == null
          ? null
          : OAuthProvider.fromConfig(
              kind: OAuthProviderKind.values.byName(raw['kind'] as String),
              id: raw['id'] as String,
              displayName: raw['displayName'] as String,
              brand: const OAuthBrand(),
              endpoints: OAuthEndpoints(
                authorization: raw['authorization'] as String,
                token: raw['token'] as String,
                userInfo: raw['userInfo'] as String?,
                issuer: raw['issuer'] as String?,
                jwks: raw['jwks'] as String?,
                responseMode: raw['responseMode'] as String?,
              ),
              scopes: [
                for (final s in raw['scopes'] as List<dynamic>) s as String,
              ],
              claims: OAuthClaimMap(
                subject: raw['subject'] as String,
                email: raw['email'] as String,
                emailVerified: raw['emailVerified'] as String?,
                name: raw['name'] as String?,
                picture: raw['picture'] as String?,
              ),
              usesPkce: raw['usesPkce'] as bool,
              linking: OAuthLinking.values.byName(raw['linking'] as String),
              clientId: raw['clientId'] as String,
              clientSecret: raw['clientSecret'] as String?,
              teamId: raw['teamId'] as String?,
              keyId: raw['keyId'] as String?,
              privateKey: raw['privateKey'] as String?,
            ),
    );
  }

  static const _path = '${Response.prefix}.auth.get_oauth_provider_config';

  final OAuthProvider? provider;

  @override
  Map<String, dynamic> toJson() {
    final provider = this.provider;
    return {
      ...super.toJson(),
      'provider': provider == null
          ? null
          : switch (provider) {
              BuiltInOAuthProvider p => {
                'kind': p.kind.name,
                'id': p.id,
                'displayName': p.displayName,
                'authorization': p.endpoints.authorization,
                'token': p.endpoints.token,
                'userInfo': p.endpoints.userInfo,
                'issuer': p.endpoints.issuer,
                'jwks': p.endpoints.jwks,
                'responseMode': p.endpoints.responseMode,
                'scopes': p.scopes,
                'subject': p.claims.subject,
                'email': p.claims.email,
                'emailVerified': p.claims.emailVerified,
                'name': p.claims.name,
                'picture': p.claims.picture,
                'usesPkce': p.usesPkce,
                'linking': p.linking.name,
                'clientId': p.clientId,
                'clientSecret': p.clientSecret,
                'teamId': p.teamId,
                'keyId': p.keyId,
                'privateKey': p.privateKey,
              },
              CustomOAuthProvider p => {
                'kind': OAuthProviderKind.custom.name,
                'id': p.id,
                'displayName': p.displayName,
                'authorization': p.endpoints.authorization,
                'token': p.endpoints.token,
                'userInfo': p.endpoints.userInfo,
                'issuer': p.endpoints.issuer,
                'jwks': p.endpoints.jwks,
                'responseMode': p.endpoints.responseMode,
                'scopes': p.scopes,
                'subject': p.claims.subject,
                'email': p.claims.email,
                'emailVerified': p.claims.emailVerified,
                'name': p.claims.name,
                'picture': p.claims.picture,
                'usesPkce': p.usesPkce,
                'linking': p.linking.name,
                'clientId': p.clientId,
                'clientSecret': p.clientSecret,
              },
            },
    };
  }
}

final class MagicLinkConfigResponse extends OperationResponse {
  const MagicLinkConfigResponse({required super.id, required this.config})
    : super(path: _path, payload: const {});

  factory MagicLinkConfigResponse.fromJson(Map<String, dynamic> json) {
    return MagicLinkConfigResponse(
      id: json['id'] as String,
      config: MagicLinkConfig.fromJson(json['config'] as Map<String, dynamic>),
    );
  }

  static const _path = '${Response.prefix}.auth.get_magic_link_base_url';

  final MagicLinkConfig config;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'config': config.toJson()};
  }
}

final class ResetPasswordConfigResponse extends OperationResponse {
  const ResetPasswordConfigResponse({required super.id, required this.config})
    : super(path: _path, payload: const {});

  factory ResetPasswordConfigResponse.fromJson(Map<String, dynamic> json) {
    return ResetPasswordConfigResponse(
      id: json['id'] as String,
      config: ResetPasswordConfig.fromJson(
        json['config'] as Map<String, dynamic>,
      ),
    );
  }

  static const _path = '${Response.prefix}.auth.get_reset_password_base_url';

  final ResetPasswordConfig config;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'config': config.toJson()};
  }
}

final class VerifyEmailConfigResponse extends OperationResponse {
  const VerifyEmailConfigResponse({required super.id, required this.config})
    : super(path: _path, payload: const {});

  factory VerifyEmailConfigResponse.fromJson(Map<String, dynamic> json) {
    return VerifyEmailConfigResponse(
      id: json['id'] as String,
      config: VerifyEmailConfig.fromJson(
        json['config'] as Map<String, dynamic>,
      ),
    );
  }

  static const _path = '${Response.prefix}.auth.get_verify_email_base_url';

  final VerifyEmailConfig config;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'config': config.toJson()};
  }
}
