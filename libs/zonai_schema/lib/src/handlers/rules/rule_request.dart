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
      case RecordRulesRequest._path:
        return RecordRulesRequest.fromRequest(request);
      case AuthTableRulesRequest._path:
        return AuthTableRulesRequest.fromRequest(request);
      case AuthRecordRulesRequest._path:
        return AuthRecordRulesRequest.fromRequest(request);
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
    return {
      ...super.toJson(),
      'table': table,
      'authType': authType.name,
    };
  }

  @override
  String toString() {
    return 'CanAuthenticateRequest(table: $table, authType: $authType)';
  }
}

final class AuthRecordRulesRequest extends RuleRequest {
  AuthRecordRulesRequest({
    required this.table,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthRecordRulesRequest._({
    required super.id,
    required this.table,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory AuthRecordRulesRequest.fromRequest(UnknownRequest request) {
    return AuthRecordRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      operation: AuthOperation.values.byName(
        request.payload['operation'] as String,
      ),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.record.auth.can_authenticate';

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
    return 'AuthRecordRulesRequest(table: $table, authType: $authType)';
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
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation,
    };
  }
}

final class RecordRulesRequest extends RuleRequest {
  RecordRulesRequest({
    required this.table,
    required this.operation,
    required this.data,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  RecordRulesRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required this.data,
    required super.jwt,
  }) : super(path: _path);

  factory RecordRulesRequest.fromRequest(UnknownRequest request) {
    return RecordRulesRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: RecordOperation.fromString(
        request.payload['operation'] as String,
      )!,
      data: request.payload['data'] as Map<String, dynamic>,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.record.can_access';

  final String table;
  final RecordOperation operation;
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

  RecordOperation get recordOperation => switch (this) {
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
}

enum RecordOperation {
  view,
  create,
  update,
  delete;

  const RecordOperation();

  static RecordOperation? fromString(String operation) {
    for (final value in values) {
      if (value.name == operation) {
        return value;
      }
    }

    return null;
  }
}
