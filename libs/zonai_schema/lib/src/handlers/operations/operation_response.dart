import 'dart:convert';

import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';
import 'package:zonai_schema/src/schemas/auth_collection.dart';

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
      ClaimsResponse._path => ClaimsResponse.fromJson(json),
      SanitizeOperationResponse._path => SanitizeOperationResponse.fromJson(
        json,
      ),
      AdminCollectionsResponse._path => AdminCollectionsResponse.fromJson(json),
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
      name: json['name'] as String,
      column: ColumnName.values.byName(json['column'] as String),
    );
  }

  static const _path = '${Response.prefix}.operation.get_column_name';

  final String name;
  final ColumnName column;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'name': name, 'column': column.name};
  }
}

final class PerformOperationResponse extends OperationResponse {
  const PerformOperationResponse({
    required super.id,
    required this.query,
    this.values = const [],
  }) : super(path: _path, payload: const {});

  factory PerformOperationResponse.fromJson(Map<String, dynamic> json) {
    return PerformOperationResponse(
      id: json['id'] as String,
      query: json['query'] as String,
      values: switch (json['values']) {
        final List<dynamic> v => List<Object?>.from(v),
        _ => const [],
      },
    );
  }

  static const _path = '${Response.prefix}.operation.perform';

  final String query;
  final List<Object?> values;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'query': query, 'values': values};
  }

  @override
  String toString() {
    return '''PerformOperationResponse:
${const JsonEncoder.withIndent('  ').convert(toJson())}
''';
  }
}

final class ClaimsResponse extends OperationResponse {
  const ClaimsResponse({
    required super.id,
    required this.claims,
    required this.isAdmin,
    required this.canEdit,
  }) : super(path: _path, payload: const {});

  factory ClaimsResponse.fromJson(Map<String, dynamic> json) {
    return ClaimsResponse(
      id: json['id'] as String,
      isAdmin: json['isAdmin'] as bool,
      canEdit: json['canEdit'] as bool,
      claims: Claims.fromJson(json['claims'] as Map<String, dynamic>),
    );
  }

  static const _path = '${Response.prefix}.auth.get_claims';

  final Claims claims;
  final bool isAdmin;
  final bool canEdit;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'claims': claims.toJson(),
      'isAdmin': isAdmin,
      'canEdit': canEdit,
    };
  }
}

final class SanitizeOperationResponse extends OperationResponse {
  SanitizeOperationResponse({
    required super.id,
    required List<Map<String, dynamic>> objects,
  }) : objects = List.unmodifiable(objects),
       super(path: _path, payload: const {});

  factory SanitizeOperationResponse.fromJson(Map<String, dynamic> json) {
    return SanitizeOperationResponse(
      id: json['id'] as String,
      objects: [
        for (final e in json['objects'] as List<dynamic>)
          Map<String, dynamic>.from(e),
      ],
    );
  }

  static const _path = '${Response.prefix}.operation.sanitize';

  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'objects': jsonDecode(jsonEncode(objects))};
  }
}

final class AdminCollectionsResponse extends OperationResponse {
  const AdminCollectionsResponse({required super.id, required this.collections})
    : super(path: _path, payload: const {});

  factory AdminCollectionsResponse.fromJson(Map<String, dynamic> json) {
    return AdminCollectionsResponse(
      id: json['id'] as String,
      collections: [
        for (final e in json['collections'] as List<dynamic>)
          (
            e['collection'] as String,
            [
              for (final authType in e['authTypes'] as List<dynamic>)
                AuthType.values.byName(authType as String),
            ],
          ),
      ],
    );
  }

  static const _path = '${Response.prefix}.auth.get_admin_collections';

  final List<(String, List<AuthType>)> collections;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collections': collections
          .map(
            (e) => {
              'collection': e.$1,
              'authTypes': e.$2.map((e) => e.name).toList(),
            },
          )
          .toList(),
    };
  }
}
