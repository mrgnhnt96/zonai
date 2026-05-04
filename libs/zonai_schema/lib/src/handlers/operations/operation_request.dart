import 'dart:convert';

import 'package:raindrop/raindrop.dart' show Filter;
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/raw_sql_filter.dart';
import 'package:zonai_schema/src/update/update.dart';

sealed class OperationRequest extends Request {
  const OperationRequest({required super.path, required super.id});

  factory OperationRequest.fromRequest(UnknownRequest request) {
    return switch (request.path) {
      PerformOperationRequest._path => PerformOperationRequest.fromRequest(
        request,
      ),
      _ => throw UnimplementedError(),
    };
  }

  @override
  String toString() {
    return '''OperationRequest:
${const JsonEncoder.withIndent('  ').convert(toJson())}
''';
  }
}

final class PerformOperationRequest extends OperationRequest {
  PerformOperationRequest({required this.collection, required this.operation})
    : super(path: _path, id: Request.generateId());

  PerformOperationRequest._({
    required super.id,
    required this.collection,
    required this.operation,
  }) : super(path: _path);

  factory PerformOperationRequest.fromRequest(UnknownRequest request) {
    final p = request.payload;
    final operation = p['operation'] as String;
    final classicOperation = CollectionOperation.fromString(operation);

    switch (classicOperation) {
      case CollectionOperation.create:
        return CreateOperationRequest.fromRequest(request);
      case CollectionOperation.update:
        return UpdateOperationRequest.fromRequest(request);
      case CollectionOperation.delete:
        return DeleteOperationRequest.fromRequest(request);
      case CollectionOperation.view:
        return ViewOperationRequest.fromRequest(request);
      case CollectionOperation.list:
        return ListOperationRequest.fromRequest(request);
      case null:
        return CustomOperationRequest.fromRequest(request);
    }
  }

  static const _path = 'operation.perform';

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

final class CreateOperationRequest extends PerformOperationRequest {
  CreateOperationRequest({required super.collection, required this.object})
    : super(operation: CollectionOperation.create.name);

  CreateOperationRequest._({
    required super.id,
    required this.object,
    required super.collection,
  }) : super._(operation: CollectionOperation.create.name);

  factory CreateOperationRequest.fromRequest(UnknownRequest request) {
    return CreateOperationRequest._(
      id: request.id,
      object: request.payload['object'] as Map<String, dynamic>,
      collection: request.payload['collection'] as String,
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

    required String where,
    required this.updates,
  }) : rawWhere = where,
       super(operation: CollectionOperation.update.name);

  UpdateOperationRequest._({
    required super.id,
    required super.collection,
    required String where,
    required this.rawWhere,
    required this.updates,
  }) : super._(operation: CollectionOperation.update.name);

  factory UpdateOperationRequest.fromRequest(UnknownRequest request) {
    return UpdateOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      where: request.payload['where'] as String,
      rawWhere: request.payload['where'] as String,
      updates: [
        for (final update in request.payload['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
    );
  }

  final String rawWhere;
  final List<Update> updates;

  Filter get where => RawSqlFilter(rawWhere);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'where': rawWhere,
      'updates': updates.map((update) => update.toJson()).toList(),
    };
  }
}

final class DeleteOperationRequest extends PerformOperationRequest {
  DeleteOperationRequest({
    required super.collection,
    required String where,
    required this.limit,
  }) : rawWhere = where,
       super(operation: CollectionOperation.delete.name);

  DeleteOperationRequest._({
    required super.id,
    required super.collection,
    required String where,
    required this.limit,
  }) : rawWhere = where,
       super._(operation: CollectionOperation.delete.name);

  factory DeleteOperationRequest.fromRequest(UnknownRequest request) {
    return DeleteOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      limit: request.payload['limit'] as int?,
      where: request.payload['where'] as String,
    );
  }

  final int? limit;
  final String rawWhere;

  Filter get where => RawSqlFilter(rawWhere);

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': rawWhere, 'limit': limit};
  }
}

final class ViewOperationRequest extends PerformOperationRequest {
  ViewOperationRequest({required super.collection, required String where})
    : rawWhere = where,
      super(operation: CollectionOperation.view.name);

  ViewOperationRequest._({
    required super.id,
    required super.collection,
    required this.rawWhere,
  }) : super._(operation: CollectionOperation.view.name);

  factory ViewOperationRequest.fromRequest(UnknownRequest request) {
    return ViewOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      rawWhere: request.payload['where'] as String?,
    );
  }

  final String? rawWhere;

  Filter? get where => switch (rawWhere) {
    null => null,
    final String filter => RawSqlFilter(filter),
  };

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': rawWhere};
  }
}

final class ListOperationRequest extends PerformOperationRequest {
  ListOperationRequest({
    required super.collection,
    required String? where,
    required this.limit,
    required this.offset,
  }) : rawWhere = where,
       super(operation: CollectionOperation.list.name);

  ListOperationRequest._({
    required super.id,
    required super.collection,
    required String? where,
    required this.limit,
    required this.offset,
  }) : rawWhere = where,
       super._(operation: CollectionOperation.list.name);

  factory ListOperationRequest.fromRequest(UnknownRequest request) {
    return ListOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      limit: request.payload['limit'] as int?,
      offset: request.payload['offset'] as int?,
      where: request.payload['where'] as String?,
    );
  }

  final int? limit;
  final int? offset;
  final String? rawWhere;

  Filter? get where => switch (rawWhere) {
    null => null,
    final String where => RawSqlFilter(where),
  };

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'where': rawWhere,
      'limit': limit,
      'offset': offset,
    };
  }
}

final class CustomOperationRequest extends PerformOperationRequest {
  CustomOperationRequest({
    required super.collection,
    required super.operation,
    required String? where,
    required this.values,
  }) : rawWhere = where;

  CustomOperationRequest._({
    required super.id,
    required super.collection,
    required super.operation,
    required String? where,
    required this.values,
  }) : rawWhere = where,
       super._();

  factory CustomOperationRequest.fromRequest(UnknownRequest request) {
    return CustomOperationRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: request.payload['operation'] as String,
      where: request.payload['where'] as String?,
      values: request.payload['values'] as Map<String, dynamic>?,
    );
  }

  final String? rawWhere;
  final Map<String, dynamic>? values;

  Filter? get where => switch (rawWhere) {
    null => null,
    final String where => RawSqlFilter(where),
  };

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'where': rawWhere, 'values': values};
  }
}
