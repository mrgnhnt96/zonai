import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class RuleRequest extends Request {
  const RuleRequest({required super.path, required super.id});

  factory RuleRequest.fromRequest(UnknownRequest request) {
    switch (request.path) {
      case CanAccessRequest._path:
        return CanAccessRequest.fromRequest(request);
      default:
        throw UnimplementedError();
    }
  }
}

final class CanAccessRequest extends RuleRequest {
  CanAccessRequest({
    required this.collection,
    required this.operation,
    this.isSuperUser = false,
  }) : super(path: _path, id: Request.generateId());
  CanAccessRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required this.isSuperUser,
  }) : super(path: _path);

  factory CanAccessRequest.fromRequest(UnknownRequest request) {
    return CanAccessRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: request.payload['operation'] as String,
      isSuperUser: request.payload['isSuperUser'] == true,
    );
  }

  static const _path = 'can_access';

  final String collection;
  final String operation;
  final bool isSuperUser;

  ClassicOperation? get classicOperation => .fromString(operation);

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

final class RecordFilterRequest extends RuleRequest {
  RecordFilterRequest({
    required this.collection,
    required this.operation,
    required this.isSuperUser,
  }) : super(path: _path, id: Request.generateId());

  RecordFilterRequest._({
    required super.id,
    required this.collection,
    required this.operation,
    required this.isSuperUser,
  }) : super(path: _path);

  factory RecordFilterRequest.fromRequest(UnknownRequest request) {
    return RecordFilterRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: request.payload['operation'] as String,
      isSuperUser: request.payload['isSuperUser'] == true,
    );
  }

  static const _path = 'record_filter';

  final String collection;
  final String operation;
  final bool isSuperUser;

  ClassicOperation? get classicOperation => .fromString(operation);

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

enum ClassicOperation {
  create,
  update,
  delete,
  view,
  list,
  search;

  const ClassicOperation();

  static ClassicOperation? fromString(String operation) {
    return switch (operation) {
      'create' => .create,
      'update' => .update,
      'delete' => .delete,
      'view' => .view,
      'list' => .list,
      'search' => .search,
      _ => null,
    };
  }
}
