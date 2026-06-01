import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';

sealed class RuleRequest extends Request {
  const RuleRequest({
    required super.path,
    required super.id,
    required super.jwt,
  });

  factory RuleRequest.fromRequest(UnknownRequest request) {
    switch (request.path) {
      case TableRulesRequest._path:
        return TableRulesRequest.fromRequest(request);
      case RowRulesRequest._path:
        return RowRulesRequest.fromRequest(request);
      case AuthTableRulesRequest._path:
        return AuthTableRulesRequest.fromRequest(request);
      case AuthRowRulesRequest._path:
        return AuthRowRulesRequest.fromRequest(request);
      default:
        throw ArgumentError('Invalid rule request path: ${request.path}');
    }
  }
}

final class AuthTableRulesRequest extends RuleRequest {
  AuthTableRulesRequest({
    required this.table,
    required this.authType,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthTableRulesRequest._({
    required super.id,
    required this.table,
    required this.authType,
    required super.jwt,
  }) : super(path: _path);

  factory AuthTableRulesRequest.fromRequest(UnknownRequest request) {
    return AuthTableRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.table.auth.can_authenticate';

  final String table;
  final AuthType authType;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'authType': authType.name};
  }

  @override
  String toString() {
    return 'CanAuthenticateRequest(table: $table, authType: $authType)';
  }
}

final class AuthRowRulesRequest extends RuleRequest {
  AuthRowRulesRequest({
    required this.table,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthRowRulesRequest._({
    required super.id,
    required this.table,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory AuthRowRulesRequest.fromRequest(UnknownRequest request) {
    return AuthRowRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      operation: AuthOperation.values.byName(
        request.payload['operation'] as String,
      ),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.row.auth.can_authenticate';

  final String table;
  final AuthType authType;
  final AuthOperation operation;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'authType': authType.name,
      'operation': operation.name,
    };
  }

  @override
  String toString() {
    return 'AuthRowRulesRequest(table: $table, authType: $authType)';
  }
}

final class TableRulesRequest extends RuleRequest {
  TableRulesRequest({
    required this.table,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  TableRulesRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory TableRulesRequest.fromRequest(UnknownRequest request) {
    return TableRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: request.payload['operation'] as String,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.table.can_access';

  final String table;
  final String operation;

  TableOperation? get classicOperation => .fromString(operation);

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'operation': operation};
  }
}

final class RowRulesRequest extends RuleRequest {
  RowRulesRequest({
    required this.table,
    required this.operation,
    required this.data,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  RowRulesRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required this.data,
    required super.jwt,
  }) : super(path: _path);

  factory RowRulesRequest.fromRequest(UnknownRequest request) {
    return RowRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: RowOperation.fromString(
        request.payload['operation'] as String,
      )!,
      data: request.payload['data'] as Map<String, dynamic>,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.row.can_access';

  final String table;
  final RowOperation operation;
  final Map<String, dynamic> data;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation.name,
      'data': data,
    };
  }
}

enum AuthOperation { signIn, signUp, passwordReset }

enum TableOperation {
  create,
  update,
  delete,
  view,
  list;

  const TableOperation();

  static TableOperation? fromString(String operation) {
    for (final value in values) {
      if (value.name == operation) {
        return value;
      }
    }
    return null;
  }

  RowOperation get rowOperation => switch (this) {
    .create => .create,
    .update => .update,
    .delete => .delete,
    .view => .view,
    .list => .view,
  };

  bool get requireObject => switch (this) {
    .create => true,
    .update => true,
    .delete => true,
    .view => false,
    .list => false,
  };

  @override
  String toString() {
    return name;
  }
}

enum RowOperation {
  view,
  create,
  update,
  delete;

  const RowOperation();

  static RowOperation? fromString(String operation) {
    for (final value in values) {
      if (value.name == operation) {
        return value;
      }
    }

    return null;
  }

  @override
  String toString() {
    return name;
  }
}
