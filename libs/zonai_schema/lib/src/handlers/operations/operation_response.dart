import 'dart:convert';

import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

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
      PasswordColumnNameResponse._path => PasswordColumnNameResponse.fromJson(
        json,
      ),
      _ => throw ArgumentError('Invalid operation response path: $path'),
    };
  }
}

final class PasswordColumnNameResponse extends OperationResponse {
  const PasswordColumnNameResponse({
    required super.id,
    required this.columnName,
  }) : super(path: _path, payload: const {});

  factory PasswordColumnNameResponse.fromJson(Map<String, dynamic> json) {
    return PasswordColumnNameResponse(
      id: json['id'] as String,
      columnName: json['columnName'] as String,
    );
  }

  static const _path = 'operation.password_column_name';

  final String columnName;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'columnName': columnName};
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

  static const _path = 'operation.perform';

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
