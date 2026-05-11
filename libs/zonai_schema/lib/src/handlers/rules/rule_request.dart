import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/schemas/auth_collection.dart';

sealed class RuleRequest extends Request {
  const RuleRequest({required super.path, required super.id});

  factory RuleRequest.fromRequest(UnknownRequest request) {
    switch (request.path) {
      case CollectionRulesRequest._path:
        return CollectionRulesRequest.fromRequest(request);
      case RecordRulesRequest._path:
        return RecordRulesRequest.fromRequest(request);
      default:
        throw UnimplementedError();
    }
  }
}

final class CanAuthenticateRequest extends RuleRequest {
  CanAuthenticateRequest({required this.collection, required this.authType})
    : super(path: _path, id: Request.generateId());

  factory CanAuthenticateRequest.fromRequest(UnknownRequest request) {
    return CanAuthenticateRequest(
      collection: request.payload['collection'] as String,
      authType: AuthType.values.byName(request.payload['authType'] as String),
    );
  }

  static const _path = 'can_authenticate';

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

final class CollectionRulesRequest extends RuleRequest {
  CollectionRulesRequest({
    required this.collection,
    required this.operation,
    this.isSuperUser = false,
  }) : super(path: _path, id: Request.generateId());

  CollectionRulesRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required this.isSuperUser,
  }) : super(path: _path);

  factory CollectionRulesRequest.fromRequest(UnknownRequest request) {
    return CollectionRulesRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: request.payload['operation'] as String,
      isSuperUser: request.payload['isSuperUser'] == true,
    );
  }

  static const _path = 'collection.can_access';

  final String collection;
  final String operation;
  final bool isSuperUser;

  CollectionOperation? get classicOperation => .fromString(operation);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'operation': operation,
      'isSuperUser': isSuperUser,
    };
  }
}

final class RecordRulesRequest extends RuleRequest {
  RecordRulesRequest({
    required this.collection,
    required this.operation,
    required this.isSuperUser,
    required this.data,
  }) : super(path: _path, id: Request.generateId());

  RecordRulesRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required this.isSuperUser,
    required this.data,
  }) : super(path: _path);

  factory RecordRulesRequest.fromRequest(UnknownRequest request) {
    return RecordRulesRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: RecordOperation.fromString(
        request.payload['operation'] as String,
      )!,
      isSuperUser: request.payload['isSuperUser'] == true,
      data: request.payload['data'] as Map<String, dynamic>,
    );
  }

  static const _path = 'record.can_access';

  final String collection;
  final RecordOperation operation;
  final bool isSuperUser;
  final Map<String, dynamic> data;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'operation': operation.name,
      'isSuperUser': isSuperUser,
      'data': data,
    };
  }
}

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
