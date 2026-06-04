import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/types/collection_actions.dart';
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
      RowRulesResponse._path => RowRulesResponse.fromJson(json),
      AuthTableRulesResponse._path => AuthTableRulesResponse.fromJson(json),
      AuthRowRulesResponse._path => AuthRowRulesResponse.fromJson(json),
      AllTableCollectionActionsResponse._path =>
        AllTableCollectionActionsResponse.fromJson(json),
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

final class AuthRowRulesResponse extends RuleResponse {
  AuthRowRulesResponse({
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

  factory AuthRowRulesResponse.fromJson(Map<String, dynamic> json) {
    return AuthRowRulesResponse(
      id: json['id'],
      table: json['table'],
      canAccess: json['canAuthenticate'],
      authType: AuthType.values.byName(json['authType']),
      operation: AuthOperation.values.byName(json['operation']),
    );
  }

  static const _path = '${Response.prefix}.row.auth.can_access';

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
    return 'AuthRowRulesResponse(table: $table, canAccess: $canAccess, authType: $authType, operation: $operation)';
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

final class AllTableCollectionActionsResponse extends RuleResponse {
  AllTableCollectionActionsResponse({required super.id, required this.actions})
    : super(
        path: _path,
        payload: {
          'actions': {
            for (final MapEntry(:key, :value) in actions.entries)
              key: value.toJson(),
          },
        },
      );

  factory AllTableCollectionActionsResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final raw = json['actions'] as Map? ?? const {};
    return AllTableCollectionActionsResponse(
      id: json['id'] as String,
      actions: {
        for (final MapEntry(:key, :value) in raw.entries)
          key as String: TableCollectionActions.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
      },
    );
  }

  static const _path = '${Response.prefix}.table.collection_actions';

  final Map<String, TableCollectionActions> actions;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'actions': {
        for (final MapEntry(:key, :value) in actions.entries)
          key: value.toJson(),
      },
    };
  }
}

final class RowRulesResponse extends RuleResponse {
  RowRulesResponse({
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

  factory RowRulesResponse.fromJson(Map<String, dynamic> json) {
    return RowRulesResponse(
      id: json['id'] as String,
      table: json['table'] as String,
      operation: RowOperation.fromString(json['operation'])!,
      canPerform: json['canPerform'] as bool,
    );
  }

  static const _path = '${Response.prefix}.row.can_access';

  final String table;
  final RowOperation operation;
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
    return 'RowRulesResponse(table: $table, operation: $operation, canPerform: $canPerform)';
  }
}
