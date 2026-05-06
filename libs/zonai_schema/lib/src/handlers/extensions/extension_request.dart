// dart format width=150
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class ExtensionRequest extends Request {
  const ExtensionRequest({required super.path, required super.id, required this.step, required this.type});

  factory ExtensionRequest.fromRequest(UnknownRequest request) {
    return switch (request.path) {
      CreateExtensionRequest._path => CreateExtensionRequest.fromRequest(request),
      BeforeUpdateExtensionRequest._path => BeforeUpdateExtensionRequest.fromRequest(request),
      AfterUpdateExtensionRequest._path => AfterUpdateExtensionRequest.fromRequest(request),
      DeleteExtensionRequest._path => DeleteExtensionRequest.fromRequest(request),
      ErrorExtensionRequest._path => ErrorExtensionRequest.fromRequest(request),
      _ => throw UnimplementedError(),
    };
  }

  final ExtensionStep step;
  final ExtensionType type;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'step': step.name, 'type': type.name};
  }
}

enum ExtensionStep { before, afterSuccess, afterError }

enum ExtensionType { create, update, delete }

final class ErrorExtensionRequest extends ExtensionRequest {
  ErrorExtensionRequest.create({required this.collection, required this.error})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .create);
  ErrorExtensionRequest.update({required this.collection, required this.error})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .update);
  ErrorExtensionRequest.delete({required this.collection, required this.error})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .delete);

  ErrorExtensionRequest._({required super.id, required this.collection, required this.error, required super.step, required super.type})
    : super(path: _path);

  factory ErrorExtensionRequest.fromRequest(UnknownRequest request) {
    return ErrorExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      error: request.payload['error'] as String,
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      type: ExtensionType.values.byName(request.payload['type'] as String),
    );
  }

  static const _path = 'extension.error';

  final String collection;
  final String error;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'error': error};
  }
}

final class CreateExtensionRequest extends ExtensionRequest {
  CreateExtensionRequest.before({required this.collection, required this.object})
    : super(path: _path, id: Request.generateId(), step: .before, type: .create);
  CreateExtensionRequest.afterSuccess({required this.collection, required this.object})
    : super(path: _path, id: Request.generateId(), step: .afterSuccess, type: .create);

  CreateExtensionRequest._({required super.id, required this.collection, required this.object, required super.step})
    : super(path: _path, type: .create);

  factory CreateExtensionRequest.fromRequest(UnknownRequest request) {
    return CreateExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      object: request.payload['object'] as Map<String, dynamic>,
      step: ExtensionStep.values.byName(request.payload['step'] as String),
    );
  }

  static const _path = 'extension.create';

  final String collection;
  final Map<String, dynamic> object;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': object};
  }
}

final class DeleteExtensionRequest extends ExtensionRequest {
  DeleteExtensionRequest.before({required this.collection, required this.objects})
    : super(path: _path, id: Request.generateId(), step: .before, type: .create);
  DeleteExtensionRequest.afterSuccess({required this.collection, required this.objects})
    : super(path: _path, id: Request.generateId(), step: .afterSuccess, type: .create);

  DeleteExtensionRequest._({required super.id, required this.collection, required this.objects, required super.step})
    : super(path: _path, type: .create);

  factory DeleteExtensionRequest.fromRequest(UnknownRequest request) {
    return DeleteExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      objects: (request.payload['object'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
    );
  }

  static const _path = 'extension.delete';

  final String collection;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': objects};
  }
}

final class BeforeUpdateExtensionRequest extends ExtensionRequest {
  BeforeUpdateExtensionRequest({required this.collection, required this.objects})
    : super(path: _path, step: .before, type: .update, id: Request.generateId());

  BeforeUpdateExtensionRequest._({required super.id, required this.collection, required this.objects, required super.step})
    : super(path: _path, type: .update);

  factory BeforeUpdateExtensionRequest.fromRequest(UnknownRequest request) {
    return BeforeUpdateExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      objects: (request.payload['object'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
    );
  }

  static const _path = 'extension.update.before';

  final String collection;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': objects};
  }
}

final class AfterUpdateExtensionRequest extends ExtensionRequest {
  AfterUpdateExtensionRequest({required this.collection, required this.before, required this.after})
    : assert(before.length == after.length, 'Before and after must have the same length'),
      super(path: _path, step: .afterSuccess, type: .update, id: Request.generateId());

  AfterUpdateExtensionRequest._({required super.id, required this.collection, required this.before, required this.after, required super.step})
    : super(path: _path, type: .update);

  factory AfterUpdateExtensionRequest.fromRequest(UnknownRequest request) {
    return AfterUpdateExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      before: (request.payload['before'] as List).cast(),
      after: (request.payload['after'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
    );
  }

  static const _path = 'extension.update.after_success';

  final String collection;
  final List<Map<String, dynamic>> before;
  final List<Map<String, dynamic>> after;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'before': before, 'after': after};
  }
}
