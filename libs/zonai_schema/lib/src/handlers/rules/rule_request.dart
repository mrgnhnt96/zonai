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
      case CollectionRulesRequest._path:
        return CollectionRulesRequest.fromRequest(request);
      case RecordRulesRequest._path:
        return RecordRulesRequest.fromRequest(request);
      case AuthCollectionRulesRequest._path:
        return AuthCollectionRulesRequest.fromRequest(request);
      case AuthRecordRulesRequest._path:
        return AuthRecordRulesRequest.fromRequest(request);
      default:
        throw ArgumentError('Invalid rule request path: ${request.path}');
    }
  }
}

final class AuthCollectionRulesRequest extends RuleRequest {
  AuthCollectionRulesRequest({
    required this.collection,
    required this.authType,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthCollectionRulesRequest._({
    required super.id,
    required this.collection,
    required this.authType,
    required super.jwt,
  }) : super(path: _path);

  factory AuthCollectionRulesRequest.fromRequest(UnknownRequest request) {
    return AuthCollectionRulesRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.collection.auth.can_authenticate';

  final String collection;
  final AuthType authType;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'authType': authType.name,
    };
  }

  @override
  String toString() {
    return 'CanAuthenticateRequest(collection: $collection, authType: $authType)';
  }
}

final class AuthRecordRulesRequest extends RuleRequest {
  AuthRecordRulesRequest({
    required this.collection,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  AuthRecordRulesRequest._({
    required super.id,
    required this.collection,
    required this.authType,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory AuthRecordRulesRequest.fromRequest(UnknownRequest request) {
    return AuthRecordRulesRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
      operation: AuthOperation.values.byName(
        request.payload['operation'] as String,
      ),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.record.auth.can_authenticate';

  final String collection;
  final AuthType authType;
  final AuthOperation operation;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'authType': authType.name,
      'operation': operation.name,
    };
  }

  @override
  String toString() {
    return 'AuthRecordRulesRequest(collection: $collection, authType: $authType)';
  }
}

final class CollectionRulesRequest extends RuleRequest {
  CollectionRulesRequest({
    required this.collection,
    required this.operation,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  CollectionRulesRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required super.jwt,
  }) : super(path: _path);

  factory CollectionRulesRequest.fromRequest(UnknownRequest request) {
    return CollectionRulesRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: request.payload['operation'] as String,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.collection.can_access';

  final String collection;
  final String operation;

  CollectionOperation? get classicOperation => .fromString(operation);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'operation': operation,
    };
  }
}

final class RecordRulesRequest extends RuleRequest {
  RecordRulesRequest({
    required this.collection,
    required this.operation,
    required this.data,
    required super.jwt,
  }) : super(path: _path, id: Request.generateId());

  RecordRulesRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required this.data,
    required super.jwt,
  }) : super(path: _path);

  factory RecordRulesRequest.fromRequest(UnknownRequest request) {
    return RecordRulesRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: RecordOperation.fromString(
        request.payload['operation'] as String,
      )!,
      data: request.payload['data'] as Map<String, dynamic>,
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.record.can_access';

  final String collection;
  final RecordOperation operation;
  final Map<String, dynamic> data;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'operation': operation.name,
      'data': data,
    };
  }
}

enum AuthOperation { signIn, signUp, passwordReset }

enum CollectionOperation {
  create,
  update,
  delete,
  view,
  list;

  const CollectionOperation();

  static CollectionOperation? fromString(String operation) {
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
