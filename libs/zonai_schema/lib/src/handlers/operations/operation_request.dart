import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';
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
      GetColumnReferenceRequest._path =>
        GetColumnReferenceRequest.fromRequest(request),
      GetClaimsOperationRequest._path => GetClaimsOperationRequest.fromRequest(
        request,
      ),
      SanitizeOperationRequest._path => SanitizeOperationRequest.fromRequest(
        request,
      ),
      GetAdminCollectionsOperationRequest._path =>
        GetAdminCollectionsOperationRequest.fromRequest(request),
      GetMagicLinkBaseUrlOperationRequest._path =>
        GetMagicLinkBaseUrlOperationRequest.fromRequest(request),
      GetResetPasswordBaseUrlOperationRequest._path =>
        GetResetPasswordBaseUrlOperationRequest.fromRequest(request),
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
  GetColumnNameRequest({required this.collection, required this.columnName})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetColumnNameRequest._({
    required super.id,
    required this.collection,
    required this.columnName,
  }) : super(path: _path, jwt: null);

  factory GetColumnNameRequest.fromRequest(UnknownRequest request) {
    return GetColumnNameRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      columnName: ColumnName.values.byName(
        request.payload['columnName'] as String,
      ),
    );
  }

  static const _path = '${Request.prefix}.operation.get_column_name';

  final String collection;
  final ColumnName columnName;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'columnName': columnName.name,
    };
  }
}

final class GetColumnReferenceRequest extends OperationRequest {
  GetColumnReferenceRequest({
    required this.collection,
    required this.columnName,
  }) : super(path: _path, id: Request.generateId(), jwt: null);

  GetColumnReferenceRequest._({
    required super.id,
    required this.collection,
    required this.columnName,
  }) : super(path: _path, jwt: null);

  factory GetColumnReferenceRequest.fromRequest(UnknownRequest request) {
    return GetColumnReferenceRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      columnName: request.payload['columnName'] as String,
    );
  }

  static const _path = '${Request.prefix}.operation.get_column_reference';

  final String collection;
  final String columnName;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'columnName': columnName,
    };
  }
}

final class PerformOperationRequest extends OperationRequest {
  PerformOperationRequest({
    required this.collection,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  PerformOperationRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory PerformOperationRequest.fromRequest(UnknownRequest request) {
    final p = request.payload;
    final operation = p['operation'] as String;
    final classicOperation = CollectionOperation.fromString(operation);

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

  final String collection;
  final String operation;

  CollectionOperation? get classicOperation =>
      CollectionOperation.fromString(operation);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
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

final class GetAdminCollectionsOperationRequest extends OperationRequest {
  GetAdminCollectionsOperationRequest()
    : super(path: _path, id: Request.generateId(), jwt: null);
  GetAdminCollectionsOperationRequest._({required super.id})
    : super(path: _path, jwt: null);

  static const _path = '${Request.prefix}.auth.get_admin_collections';

  factory GetAdminCollectionsOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetAdminCollectionsOperationRequest._(id: request.id);
  }
}

final class ViewAuthOperationRequest extends OperationRequest {
  ViewAuthOperationRequest({
    required this.collection,
    required this.payload,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  ViewAuthOperationRequest._({
    required super.id,
    required this.collection,
    required this.payload,
    required super.jwt,
  }) : super(path: _path);

  factory ViewAuthOperationRequest.fromRequest(UnknownRequest request) {
    return ViewAuthOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      payload: AuthOperationPayload.fromJson(
        request.payload['payload'] as Map<String, dynamic>,
      ),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.auth.view';

  final AuthOperationPayload payload;
  final String collection;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'payload': payload.toJson(),
    };
  }
}

final class CreateAuthOperationRequest extends OperationRequest {
  CreateAuthOperationRequest({
    required this.collection,
    required this.payload,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  CreateAuthOperationRequest._({
    required super.id,
    required this.payload,
    required this.collection,
    required super.jwt,
  }) : super(path: _path);

  factory CreateAuthOperationRequest.fromRequest(UnknownRequest request) {
    return CreateAuthOperationRequest._(
      id: request.id,
      payload: AuthOperationPayload.fromJson(
        request.payload['payload'] as Map<String, dynamic>,
      ),
      collection: request.payload['collection'] as String,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.auth.create';

  final String collection;
  final AuthOperationPayload payload;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'payload': payload.toJson(),
    };
  }
}

final class CreateOperationRequest extends PerformOperationRequest {
  CreateOperationRequest({
    required super.collection,
    required this.object,
    required super.jwt,
  }) : super(operation: CollectionOperation.create.name);

  CreateOperationRequest._({
    required super.id,
    required this.object,
    required super.collection,
    required super.jwt,
  }) : super._(operation: CollectionOperation.create.name);

  factory CreateOperationRequest.fromRequest(UnknownRequest request) {
    return CreateOperationRequest._(
      id: request.id,
      object: request.payload['object'] as Map<String, dynamic>,
      collection: request.payload['collection'] as String,
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
    required super.collection,
    required this.where,
    required this.updates,
    required super.jwt,
  }) : super(operation: CollectionOperation.update.name);

  UpdateOperationRequest._({
    required super.id,
    required super.collection,
    required this.where,
    required this.updates,
    required super.jwt,
  }) : super._(operation: CollectionOperation.update.name);

  factory UpdateOperationRequest.fromRequest(UnknownRequest request) {
    return UpdateOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
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
    required super.collection,
    required this.where,
    required this.limit,
    required super.jwt,
  }) : super(operation: CollectionOperation.delete.name);

  DeleteOperationRequest._({
    required super.id,
    required super.collection,
    required this.where,
    required this.limit,
    required super.jwt,
  }) : super._(operation: CollectionOperation.delete.name);

  factory DeleteOperationRequest.fromRequest(UnknownRequest request) {
    return DeleteOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
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
    required super.collection,
    required this.where,
    super.jwt,
  }) : super(operation: CollectionOperation.view.name);

  ReadOperationRequest._({
    required super.id,
    required super.collection,
    required this.where,
    required super.jwt,
  }) : super._(operation: CollectionOperation.view.name);

  factory ReadOperationRequest.fromRequest(UnknownRequest request) {
    return ReadOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
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
    required super.collection,
    required this.where,
    required this.limit,
    required this.offset,
    required super.jwt,
  }) : super(operation: CollectionOperation.list.name);

  ListOperationRequest._({
    required super.id,
    required super.collection,
    required this.where,
    required this.limit,
    required this.offset,
    required super.jwt,
  }) : super._(operation: CollectionOperation.list.name);

  factory ListOperationRequest.fromRequest(UnknownRequest request) {
    return ListOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      limit: request.payload['limit'] as int?,
      offset: request.payload['offset'] as int?,
      where: switch (request.payload['where']) {
        final Map<String, dynamic> json => Where.fromJson(json),
        _ => null,
      },
      jwt: request.jwt,
    );
  }

  final int? limit;
  final int? offset;
  final Where? where;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'where': where?.toJson(),
      'limit': limit,
      'offset': offset,
    };
  }
}

final class CustomOperationRequest extends PerformOperationRequest {
  CustomOperationRequest({
    required super.collection,
    required super.operation,
    required this.where,
    required this.values,
    required super.jwt,
  });

  CustomOperationRequest._({
    required super.id,
    required super.collection,
    required super.operation,
    required this.where,
    required this.values,
    required super.jwt,
  }) : super._();

  factory CustomOperationRequest.fromRequest(UnknownRequest request) {
    return CustomOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
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

final class GetClaimsOperationRequest extends OperationRequest {
  GetClaimsOperationRequest({required this.collection, required this.jwt})
    : super(path: _path, id: Request.generateId(), jwt: jwt);

  GetClaimsOperationRequest._({
    required super.id,
    required this.collection,
    required this.jwt,
  }) : super(path: _path, jwt: jwt);

  factory GetClaimsOperationRequest.fromRequest(UnknownRequest request) {
    return GetClaimsOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      jwt:
          request.jwt ??
          (throw StateError('JWT is required for this operation')),
    );
  }

  static const _path = '${Request.prefix}.auth.get_claims';

  final String collection;
  final Jwt jwt;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection};
  }
}

final class SanitizeOperationRequest extends OperationRequest {
  SanitizeOperationRequest({
    required this.collection,
    required List<Map<String, dynamic>> objects,
  }) : objects = List.unmodifiable(objects),
       super(path: _path, id: Request.generateId(), jwt: null);

  SanitizeOperationRequest._({
    required super.id,
    required this.collection,
    required List<Map<String, dynamic>> objects,
  }) : objects = List.unmodifiable(objects),
       super(path: _path, jwt: null);

  factory SanitizeOperationRequest.fromRequest(UnknownRequest request) {
    return SanitizeOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      objects: [
        for (final e in request.payload['objects'] as List<dynamic>)
          Map<String, dynamic>.from(e),
      ],
    );
  }

  static const _path = '${Request.prefix}.operation.sanitize';

  final String collection;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'objects': objects};
  }
}

final class CountOperationRequest extends PerformOperationRequest {
  CountOperationRequest({
    required super.collection,
    required this.where,
    super.jwt,
  }) : super(operation: CollectionOperation.list.name);

  CountOperationRequest._({
    required super.id,
    required super.collection,
    required this.where,
    required super.jwt,
  }) : super._(operation: CollectionOperation.list.name);

  factory CountOperationRequest.fromRequest(UnknownRequest request) {
    return CountOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
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

final class GetMagicLinkBaseUrlOperationRequest extends OperationRequest {
  GetMagicLinkBaseUrlOperationRequest({required this.collection})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetMagicLinkBaseUrlOperationRequest._({
    required super.id,
    required this.collection,
  }) : super(path: _path, jwt: null);

  factory GetMagicLinkBaseUrlOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetMagicLinkBaseUrlOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
    );
  }

  static const _path = '${Request.prefix}.auth.get_magic_link_base_url';

  final String collection;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection};
  }
}

final class GetResetPasswordBaseUrlOperationRequest extends OperationRequest {
  GetResetPasswordBaseUrlOperationRequest({required this.collection})
    : super(path: _path, id: Request.generateId(), jwt: null);

  GetResetPasswordBaseUrlOperationRequest._({
    required super.id,
    required this.collection,
  }) : super(path: _path, jwt: null);

  factory GetResetPasswordBaseUrlOperationRequest.fromRequest(
    UnknownRequest request,
  ) {
    return GetResetPasswordBaseUrlOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
    );
  }

  static const _path = '${Request.prefix}.auth.get_reset_password_base_url';

  final String collection;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection};
  }
}
