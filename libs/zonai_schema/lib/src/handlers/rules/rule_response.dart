import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';

sealed class RuleResponse extends Response {
  const RuleResponse({
    required super.path,
    required super.id,
    required super.payload,
  });

  factory RuleResponse.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid rule response path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid rule response id: ${json['id']}');
    }

    return switch (path) {
      TableRulesResponse._path => TableRulesResponse.fromJson(json),
      RecordRulesResponse._path => RecordRulesResponse.fromJson(json),
      AuthTableRulesResponse._path => AuthTableRulesResponse.fromJson(
        json,
      ),
      AuthRecordRulesResponse._path => AuthRecordRulesResponse.fromJson(json),
      _ => throw ArgumentError('Invalid rule response path: $path'),
    };
  }
}

final class AuthTableRulesResponse extends RuleResponse {
  AuthTableRulesResponse({
    required super.id,
    required this.table,
    required this.canAuthenticate,
    required this.authType,
  }) : super(
         path: _path,
         payload: {
           'table': table,
           'canAuthenticate': canAuthenticate,
           'authType': authType.name,
         },
       );

  factory AuthTableRulesResponse.fromJson(Map<String, dynamic> json) {
    return AuthTableRulesResponse(
      id: json['id'],
      table: json['table'],
      canAuthenticate: json['canAuthenticate'],
      authType: AuthType.values.byName(json['authType']),
    );
  }

  static const _path = '${Response.prefix}.table.auth.can_authenticate';

  final String table;
  final bool canAuthenticate;
  final AuthType authType;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'canAuthenticate': canAuthenticate,
      'authType': authType.name,
    };
  }

  @override
  String toString() {
    return 'AuthTableRulesResponse(table: $table, canAuthenticate: $canAuthenticate, authType: $authType)';
  }
}

final class AuthRecordRulesResponse extends RuleResponse {
  AuthRecordRulesResponse({
    required super.id,
    required this.table,
    required this.canAccess,
    required this.authType,
    required this.operation,
  }) : super(
         path: _path,
         payload: {
           'table': table,
           'canAuthenticate': canAccess,
           'authType': authType.name,
           'operation': operation.name,
         },
       );

  factory AuthRecordRulesResponse.fromJson(Map<String, dynamic> json) {
    return AuthRecordRulesResponse(
      id: json['id'],
      table: json['table'],
      canAccess: json['canAuthenticate'],
      authType: AuthType.values.byName(json['authType']),
      operation: AuthOperation.values.byName(json['operation']),
    );
  }

  static const _path = '${Response.prefix}.record.auth.can_access';

  final String table;
  final bool canAccess;
  final AuthType authType;
  final AuthOperation operation;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'canAuthenticate': canAccess,
      'authType': authType.name,
      'operation': operation.name,
    };
  }

  @override
  String toString() {
    return 'AuthRecordRulesResponse(table: $table, canAccess: $canAccess, authType: $authType, operation: $operation)';
  }
}

final class TableRulesResponse extends RuleResponse {
  TableRulesResponse({
    required super.id,
    required this.table,
    required this.operation,
    required this.canAccess,
  }) : super(
         path: _path,
         payload: {
           'table': table,
           'operation': operation,
           'canAccess': canAccess,
         },
       );

  factory TableRulesResponse.fromJson(Map<String, dynamic> json) {
    return TableRulesResponse(
      id: json['id'],
      table: json['table'],
      operation: json['operation'],
      canAccess: json['canAccess'],
    );
  }

  static const _path = '${Response.prefix}.table.can_access';

  final String table;
  final String operation;
  final bool canAccess;

  @override
  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'operation': operation,
      'canAccess': canAccess,
      ...super.toJson(),
    };
  }

  @override
  String toString() {
    return 'TableRulesResponse(table: $table, operation: $operation, canAccess: $canAccess)';
  }
}

final class RecordRulesResponse extends RuleResponse {
  RecordRulesResponse({
    required super.id,
    required this.table,
    required this.operation,
    required this.canPerform,
  }) : super(
         path: _path,
         payload: {
           'table': table,
           'operation': operation.name,
           'canPerform': canPerform,
         },
       );

  factory RecordRulesResponse.fromJson(Map<String, dynamic> json) {
    return RecordRulesResponse(
      id: json['id'] as String,
      table: json['table'] as String,
      operation: RecordOperation.fromString(json['operation'])!,
      canPerform: json['canPerform'] as bool,
    );
  }

  static const _path = '${Response.prefix}.record.can_access';

  final String table;
  final RecordOperation operation;
  final bool canPerform;

  @override
  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'operation': operation.name,
      'canPerform': canPerform,
      ...super.toJson(),
    };
  }

  @override
  String toString() {
    return 'RecordRulesResponse(table: $table, operation: $operation, canPerform: $canPerform)';
  }
}
