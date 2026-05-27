import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';
import 'package:zonai_schema/src/types/order_by.dart';
import 'package:zonai_schema/src/types/where.dart';
import 'package:zonai_schema/src/update/update.dart';

sealed class OperationRequest extends Request {
  const OperationRequest({
    required super.path,
    required super.id,
    required super.jwt,
  });

  factory OperationRequest.fromRequest(UnknownRequest request) {
    return switch (request.path) {
      PerformOperationRequest._path => PerformOperationRequest.fromRequest(
        request,
      ),
      ViewAuthOperationRequest._path => ViewAuthOperationRequest.fromRequest(
        request,
      ),
      CreateAuthOperationRequest._path =>
        CreateAuthOperationRequest.fromRequest(request),
      GetColumnNameRequest._path => GetColumnNameRequest.fromRequest(request),
      GetColumnReferenceRequest._path => GetColumnReferenceRequest.fromRequest(
        request,
      ),
      GetJwtConfigOperationRequest._path =>
        GetJwtConfigOperationRequest.fromRequest(request),
      SanitizeOperationRequest._path => SanitizeOperationRequest.fromRequest(
        request,
      ),
      GetAdminTablesOperationRequest._path =>
        GetAdminTablesOperationRequest.fromRequest(request),
      GetMagicLinkConfigOperationRequest._path =>
        GetMagicLinkConfigOperationRequest.fromRequest(request),
      GetResetPasswordConfigOperationRequest._path =>
        GetResetPasswordConfigOperationRequest.fromRequest(request),
      GetVerifyEmailConfigOperationRequest._path =>
        GetVerifyEmailConfigOperationRequest.fromRequest(request),
      _ => throw ArgumentError(
        'Invalid operation request path: ${request.path}',
      ),
    };
  }

  @override
  String toString() {
    return '''OperationRequest:
${const JsonEncoder.withIndent('  ').convert(toJson())}
''';
  }
}

enum ColumnName { password, id, isVerified, email }

final class GetColumnNameRequest extends OperationRequest {
  GetColumnNameRequest({required this.table, required this.columnName})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetColumnNameRequest._({
    required super.id,
    required this.table,
    required this.columnName,
  }) : super(path: _path, jwt: null);

  factory GetColumnNameRequest.fromRequest(UnknownRequest request) {
    return GetColumnNameRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      columnName: ColumnName.values.byName(
        request.payload['columnName'] as String,
      ),
    );
  }

  static const _path = '${Request.prefix}.operation.get_column_name';

  final String table;
  final ColumnName columnName;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'columnName': columnName.name,
    };
  }
}

final class GetColumnReferenceRequest extends OperationRequest {
  GetColumnReferenceRequest({
    required this.table,
    required this.columnName,
  }) : super(path: _path, id: Request.generateId(), jwt: null);

  GetColumnReferenceRequest._({
    required super.id,
    required this.table,
    required this.columnName,
  }) : super(path: _path, jwt: null);

  factory GetColumnReferenceRequest.fromRequest(UnknownRequest request) {
    return GetColumnReferenceRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      columnName: request.payload['columnName'] as String,
    );
  }

  static const _path = '${Request.prefix}.operation.get_column_reference';

  final String table;
  final String columnName;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'columnName': columnName,
    };
  }
}

final class PerformOperationRequest extends OperationRequest {
  PerformOperationRequest({
    required this.table,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  PerformOperationRequest._({
    required super.id,
    required this.table,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory PerformOperationRequest.fromRequest(UnknownRequest request) {
    final p = request.payload;
    final operation = p['operation'] as String;
    final classicOperation = TableOperation.fromString(operation);

    switch (classicOperation) {
      case .create:
        return CreateOperationRequest.fromRequest(request);
      case .update:
        return UpdateOperationRequest.fromRequest(request);
      case .delete:
        return DeleteOperationRequest.fromRequest(request);
      case .view:
        return ReadOperationRequest.fromRequest(request);
      case .list:
        return ListOperationRequest.fromRequest(request);
      case null:
        return CustomOperationRequest.fromRequest(request);
    }
  }

  static const _path = '${Request.prefix}.operation.perform';

  final String table;
  final String operation;

  TableOperation? get classicOperation =>
      TableOperation.fromString(operation);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation,
    };
  }
}

sealed class AuthOperationPayload {
  const AuthOperationPayload({required this.authType});

  factory AuthOperationPayload.fromJson(Map<String, dynamic> json) {
    return switch (AuthType.values.byName(json['authType'] as String)) {
      .password => PasswordAuthOperationPayload.fromJson(json),
      .otp => OtpAuthOperationPayload.fromJson(json),
      .magicLink => MagicLinkAuthOperationPayload.fromJson(json),
    };
  }

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'authType': authType.name};
  }

  final AuthType authType;
}

final class OtpAuthOperationPayload extends AuthOperationPayload {
  const OtpAuthOperationPayload.get({required this.email})
    : object = null,
      super(authType: .otp);
  const OtpAuthOperationPayload.save({
    required this.email,
    required this.object,
  }) : super(authType: .otp);
  const OtpAuthOperationPayload._({required this.email, required this.object})
    : super(authType: .otp);
  factory OtpAuthOperationPayload.fromJson(Map<String, dynamic> json) {
    return OtpAuthOperationPayload._(
      email: json['email'] as String,
      object: json['object'] as Map<String, dynamic>?,
    );
  }

  final String email;
  final Map<String, dynamic>? object;

  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'email': email,
      'object': jsonDecode(jsonEncode(object)),
    };
  }
}

final class MagicLinkAuthOperationPayload extends AuthOperationPayload {
  const MagicLinkAuthOperationPayload.get({required this.email})
    : object = null,
      super(authType: .otp);
  const MagicLinkAuthOperationPayload.save({
    required this.email,
    required this.object,
  }) : super(authType: .otp);
  const MagicLinkAuthOperationPayload._({
    required this.email,
    required this.object,
  }) : super(authType: .otp);
  factory MagicLinkAuthOperationPayload.fromJson(Map<String, dynamic> json) {
    return MagicLinkAuthOperationPayload._(
      email: json['email'] as String,
      object: json['object'] as Map<String, dynamic>?,
    );
  }

  final String email;
  final Map<String, dynamic>? object;

  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'email': email,
      'object': jsonDecode(jsonEncode(object)),
    };
  }
}

final class PasswordAuthOperationPayload extends AuthOperationPayload {
  const PasswordAuthOperationPayload.save({
    required this.email,
    required String this.passwordHash,
    required this.object,
  }) : super(authType: .password);

  const PasswordAuthOperationPayload.get({required this.email})
    : passwordHash = null,
      object = null,
      super(authType: .password);

  PasswordAuthOperationPayload._({
    required this.email,
    required this.passwordHash,
    required this.object,
  }) : super(authType: .password);

  factory PasswordAuthOperationPayload.fromJson(Map<String, dynamic> json) {
    return PasswordAuthOperationPayload._(
      email: json['email'] as String,
      passwordHash: json['passwordHash'] as String?,
      object: json['object'] as Map<String, dynamic>?,
    );
  }

  final String email;
  final String? passwordHash;
  final Map<String, dynamic>? object;

  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'email': email,
      'passwordHash': passwordHash,
      'object': object,
    };
  }
}

final class GetAdminTablesOperationRequest extends OperationRequest {
  GetAdminTablesOperationRequest()
    : super(path: _path, id: Request.generateId(), jwt: null);
  GetAdminTablesOperationRequest._({required super.id})
    : super(path: _path, jwt: null);

  static const _path = '${Request.prefix}.auth.get_admin_tables';

  factory GetAdminTablesOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetAdminTablesOperationRequest._(id: request.id);
  }
}

final class ViewAuthOperationRequest extends OperationRequest {
  ViewAuthOperationRequest({
    required this.table,
    required this.payload,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  ViewAuthOperationRequest._({
    required super.id,
    required this.table,
    required this.payload,
    required super.jwt,
  }) : super(path: _path);

  factory ViewAuthOperationRequest.fromRequest(UnknownRequest request) {
    return ViewAuthOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      payload: AuthOperationPayload.fromJson(
        request.payload['payload'] as Map<String, dynamic>,
      ),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.auth.view';

  final AuthOperationPayload payload;
  final String table;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'payload': payload.toJson(),
    };
  }
}

final class CreateAuthOperationRequest extends OperationRequest {
  CreateAuthOperationRequest({
    required this.table,
    required this.payload,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  CreateAuthOperationRequest._({
    required super.id,
    required this.payload,
    required this.table,
    required super.jwt,
  }) : super(path: _path);

  factory CreateAuthOperationRequest.fromRequest(UnknownRequest request) {
    return CreateAuthOperationRequest._(
      id: request.id,
      payload: AuthOperationPayload.fromJson(
        request.payload['payload'] as Map<String, dynamic>,
      ),
      table: request.payload['table'] as String,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.auth.create';

  final String table;
  final AuthOperationPayload payload;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'payload': payload.toJson(),
    };
  }
}

final class CreateOperationRequest extends PerformOperationRequest {
  CreateOperationRequest({
    required super.table,
    required this.object,
    required super.jwt,
  }) : super(operation: TableOperation.create.name);

  CreateOperationRequest._({
    required super.id,
    required this.object,
    required super.table,
    required super.jwt,
  }) : super._(operation: TableOperation.create.name);

  factory CreateOperationRequest.fromRequest(UnknownRequest request) {
    return CreateOperationRequest._(
      id: request.id,
      object: request.payload['object'] as Map<String, dynamic>,
      table: request.payload['table'] as String,
      jwt: request.jwt,
    );
  }

  final Map<String, dynamic> object;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'object': object};
  }
}

final class UpdateOperationRequest extends PerformOperationRequest {
  UpdateOperationRequest({
    required super.table,
    required this.where,
    required this.updates,
    required super.jwt,
  }) : super(operation: TableOperation.update.name);

  UpdateOperationRequest._({
    required super.id,
    required super.table,
    required this.where,
    required this.updates,
    required super.jwt,
  }) : super._(operation: TableOperation.update.name);

  factory UpdateOperationRequest.fromRequest(UnknownRequest request) {
    return UpdateOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      where: Where.fromJson(request.payload['where'] as Map<String, dynamic>),
      updates: [
        for (final update in request.payload['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
      jwt: request.jwt,
    );
  }

  final Where where;
  final List<Update> updates;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'where': where.toJson(),
      'updates': updates.map((update) => update.toJson()).toList(),
    };
  }
}

final class DeleteOperationRequest extends PerformOperationRequest {
  DeleteOperationRequest({
    required super.table,
    required this.where,
    required this.limit,
    required super.jwt,
  }) : super(operation: TableOperation.delete.name);

  DeleteOperationRequest._({
    required super.id,
    required super.table,
    required this.where,
    required this.limit,
    required super.jwt,
  }) : super._(operation: TableOperation.delete.name);

  factory DeleteOperationRequest.fromRequest(UnknownRequest request) {
    return DeleteOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      limit: request.payload['limit'] as int?,
      where: Where.fromJson(request.payload['where'] as Map<String, dynamic>),
      jwt: request.jwt,
    );
  }

  final int? limit;
  final Where where;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': where.toJson(), 'limit': limit};
  }
}

final class ReadOperationRequest extends PerformOperationRequest {
  ReadOperationRequest({
    required super.table,
    required this.where,
    super.jwt,
  }) : super(operation: TableOperation.view.name);

  ReadOperationRequest._({
    required super.id,
    required super.table,
    required this.where,
    required super.jwt,
  }) : super._(operation: TableOperation.view.name);

  factory ReadOperationRequest.fromRequest(UnknownRequest request) {
    return ReadOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      where: Where.fromJson(request.payload['where'] as Map<String, dynamic>),
      jwt: request.jwt,
    );
  }

  final Where where;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': where.toJson()};
  }
}

final class ListOperationRequest extends PerformOperationRequest {
  ListOperationRequest({
    required super.table,
    required this.where,
    required this.limit,
    required this.offset,
    this.orderBy,
    required super.jwt,
  }) : super(operation: TableOperation.list.name);

  ListOperationRequest._({
    required super.id,
    required super.table,
    required this.where,
    required this.limit,
    required this.offset,
    this.orderBy,
    required super.jwt,
  }) : super._(operation: TableOperation.list.name);

  factory ListOperationRequest.fromRequest(UnknownRequest request) {
    return ListOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      limit: request.payload['limit'] as int?,
      offset: request.payload['offset'] as int?,
      where: switch (request.payload['where']) {
        final Map<String, dynamic> json => Where.fromJson(json),
        _ => null,
      },
      orderBy: switch (request.payload['order_by']) {
        null => null,
        final List list => [
          for (final item in list)
            OrderByTerm.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        final value => throw ArgumentError.value(
          value,
          'order_by',
          'Expected a list of order terms',
        ),
      },
      jwt: request.jwt,
    );
  }

  final int? limit;
  final int? offset;
  final Where? where;
  final List<OrderByTerm>? orderBy;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'where': where?.toJson(),
      'limit': limit,
      'offset': offset,
      'order_by': ?switch (orderBy) {
        null => null,
        final terms when terms.isNotEmpty => [
          for (final term in terms) term.toJson(),
        ],
        _ => null,
      },
    };
  }
}

final class CustomOperationRequest extends PerformOperationRequest {
  CustomOperationRequest({
    required super.table,
    required super.operation,
    required this.where,
    required this.values,
    required super.jwt,
  });

  CustomOperationRequest._({
    required super.id,
    required super.table,
    required super.operation,
    required this.where,
    required this.values,
    required super.jwt,
  }) : super._();

  factory CustomOperationRequest.fromRequest(UnknownRequest request) {
    return CustomOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: request.payload['operation'] as String,
      where: switch (request.payload['where']) {
        final Map<String, dynamic> json => Where.fromJson(json),
        _ => null,
      },
      values: request.payload['values'] as Map<String, dynamic>?,
      jwt: request.jwt,
    );
  }

  final Where? where;
  final Map<String, dynamic>? values;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': where?.toJson(), 'values': values};
  }
}

final class GetJwtConfigOperationRequest extends OperationRequest {
  GetJwtConfigOperationRequest({required this.table, required this.jwt})
    : super(path: _path, id: Request.generateId(), jwt: jwt);

  GetJwtConfigOperationRequest._({
    required super.id,
    required this.table,
    required this.jwt,
  }) : super(path: _path, jwt: jwt);

  factory GetJwtConfigOperationRequest.fromRequest(UnknownRequest request) {
    return GetJwtConfigOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      jwt:
          request.jwt ??
          (throw StateError('JWT is required for this operation')),
    );
  }

  static const _path = '${Request.prefix}.auth.get_jwt_config';

  final String table;
  final Jwt jwt;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table};
  }
}

final class SanitizeOperationRequest extends OperationRequest {
  SanitizeOperationRequest({
    required this.table,
    required List<Map<String, dynamic>> objects,
  }) : objects = List.unmodifiable(objects),
       super(path: _path, id: Request.generateId(), jwt: null);

  SanitizeOperationRequest._({
    required super.id,
    required this.table,
    required List<Map<String, dynamic>> objects,
  }) : objects = List.unmodifiable(objects),
       super(path: _path, jwt: null);

  factory SanitizeOperationRequest.fromRequest(UnknownRequest request) {
    return SanitizeOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      objects: [
        for (final e in request.payload['objects'] as List<dynamic>)
          Map<String, dynamic>.from(e),
      ],
    );
  }

  static const _path = '${Request.prefix}.operation.sanitize';

  final String table;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'objects': objects};
  }
}

final class CountOperationRequest extends PerformOperationRequest {
  CountOperationRequest({
    required super.table,
    required this.where,
    super.jwt,
  }) : super(operation: TableOperation.list.name);

  CountOperationRequest._({
    required super.id,
    required super.table,
    required this.where,
    required super.jwt,
  }) : super._(operation: TableOperation.list.name);

  factory CountOperationRequest.fromRequest(UnknownRequest request) {
    return CountOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      where: switch (request.payload['where']) {
        final Map<String, dynamic> json => Where.fromJson(json),
        _ => null,
      },
      jwt: request.jwt,
    );
  }

  final Where? where;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': where?.toJson()};
  }
}

final class GetMagicLinkConfigOperationRequest extends OperationRequest {
  GetMagicLinkConfigOperationRequest({required this.table})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetMagicLinkConfigOperationRequest._({
    required super.id,
    required this.table,
  }) : super(path: _path, jwt: null);

  factory GetMagicLinkConfigOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetMagicLinkConfigOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
    );
  }

  static const _path = '${Request.prefix}.auth.get_magic_link_base_url';

  final String table;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table};
  }
}

final class GetResetPasswordConfigOperationRequest extends OperationRequest {
  GetResetPasswordConfigOperationRequest({required this.table})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetResetPasswordConfigOperationRequest._({
    required super.id,
    required this.table,
  }) : super(path: _path, jwt: null);

  factory GetResetPasswordConfigOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetResetPasswordConfigOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
    );
  }

  static const _path = '${Request.prefix}.auth.get_reset_password_base_url';

  final String table;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table};
  }
}

final class GetVerifyEmailConfigOperationRequest extends OperationRequest {
  GetVerifyEmailConfigOperationRequest({required this.table})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetVerifyEmailConfigOperationRequest._({
    required super.id,
    required this.table,
  }) : super(path: _path, jwt: null);

  factory GetVerifyEmailConfigOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetVerifyEmailConfigOperationRequest._(
      id: request.id,
      table: request.payload['table'] as String,
    );
  }

  static const _path = '${Request.prefix}.auth.get_verify_email_base_url';

  final String table;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table};
  }
}
