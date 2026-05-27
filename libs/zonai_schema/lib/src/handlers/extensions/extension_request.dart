// dart format width=150
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class ExtensionRequest extends Request {
  const ExtensionRequest({required super.path, required super.id, required super.jwt});

  factory ExtensionRequest.fromRequest(UnknownRequest request) {
    return switch (request.path) {
      CreateExtensionRequest._path => CreateExtensionRequest.fromRequest(request),
      BeforeUpdateExtensionRequest._path => BeforeUpdateExtensionRequest.fromRequest(request),
      AfterUpdateExtensionRequest._path => AfterUpdateExtensionRequest.fromRequest(request),
      DeleteExtensionRequest._path => DeleteExtensionRequest.fromRequest(request),
      ErrorExtensionRequest._path => ErrorExtensionRequest.fromRequest(request),
      AuthExtensionRequest._path => AuthExtensionRequest.fromRequest(request),
      _ => throw ArgumentError('Invalid extension request path: ${request.path}'),
    };
  }
}

enum ExtensionStep { before, afterSuccess, afterError }

enum ExtensionType { create, update, delete }

enum AuthExtensionStep { onSignUp, onSignIn, onRefresh, onLogout, onPasswordReset }

/// The [jwt] belongs to the user who is making the request, not the user that is being created or signed in.
final class AuthExtensionRequest extends ExtensionRequest {
  AuthExtensionRequest.onSignUp({required this.collection, required this.object, required super.jwt})
    : step = .onSignUp,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onSignIn({required this.collection, required this.object, required super.jwt})
    : step = .onSignIn,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onRefresh({required this.collection, required this.object, required super.jwt})
    : step = .onRefresh,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onLogout({required this.collection, required this.object, required super.jwt})
    : step = .onLogout,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onPasswordReset({required this.collection, required this.object, required super.jwt})
    : step = .onPasswordReset,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest._({required super.id, required this.collection, required this.object, required this.step, required super.jwt})
    : super(path: _path);

  factory AuthExtensionRequest.fromRequest(UnknownRequest request) {
    return AuthExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      object: request.payload['object'] as Map<String, dynamic>,
      step: AuthExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.auth';

  final String collection;
  final Map<String, dynamic> object;
  final AuthExtensionStep step;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': object, 'step': step.name};
  }
}

sealed class RecordExtensionRequest extends ExtensionRequest {
  const RecordExtensionRequest({required super.path, required super.id, required this.step, required this.type, required super.jwt});

  final ExtensionStep step;
  final ExtensionType type;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'step': step.name, 'type': type.name};
  }
}

final class ErrorExtensionRequest extends RecordExtensionRequest {
  ErrorExtensionRequest.create({required this.collection, required this.error, required super.jwt})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .create);
  ErrorExtensionRequest.update({required this.collection, required this.error, required super.jwt})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .update);
  ErrorExtensionRequest.delete({required this.collection, required this.error, required super.jwt})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .delete);

  ErrorExtensionRequest._({
    required super.id,
    required this.collection,
    required this.error,
    required super.step,
    required super.type,
    required super.jwt,
  }) : super(path: _path);

  factory ErrorExtensionRequest.fromRequest(UnknownRequest request) {
    return ErrorExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      error: request.payload['error'] as String,
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      type: ExtensionType.values.byName(request.payload['type'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.error';

  final String collection;
  final String error;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'error': error};
  }
}

final class CreateExtensionRequest extends RecordExtensionRequest {
  CreateExtensionRequest.before({required this.collection, required this.object, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .before, type: .create);
  CreateExtensionRequest.afterSuccess({required this.collection, required this.object, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .afterSuccess, type: .create);

  CreateExtensionRequest._({required super.id, required this.collection, required this.object, required super.step, required super.jwt})
    : super(path: _path, type: .create);

  factory CreateExtensionRequest.fromRequest(UnknownRequest request) {
    return CreateExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      object: request.payload['object'] as Map<String, dynamic>,
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.create';

  final String collection;
  final Map<String, dynamic> object;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': object};
  }
}

final class DeleteExtensionRequest extends RecordExtensionRequest {
  DeleteExtensionRequest.before({required this.collection, required this.objects, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .before, type: .create);
  DeleteExtensionRequest.afterSuccess({required this.collection, required this.objects, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .afterSuccess, type: .create);

  DeleteExtensionRequest._({required super.id, required this.collection, required this.objects, required super.step, required super.jwt})
    : super(path: _path, type: .create);

  factory DeleteExtensionRequest.fromRequest(UnknownRequest request) {
    return DeleteExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      objects: (request.payload['object'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.delete';

  final String collection;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': objects};
  }
}

final class BeforeUpdateExtensionRequest extends RecordExtensionRequest {
  BeforeUpdateExtensionRequest({required this.collection, required this.objects, required super.jwt})
    : super(path: _path, step: .before, type: .update, id: Request.generateId());

  BeforeUpdateExtensionRequest._({required super.id, required this.collection, required this.objects, required super.step, required super.jwt})
    : super(path: _path, type: .update);

  factory BeforeUpdateExtensionRequest.fromRequest(UnknownRequest request) {
    return BeforeUpdateExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      objects: (request.payload['object'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.update.before';

  final String collection;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'object': objects};
  }
}

final class AfterUpdateExtensionRequest extends RecordExtensionRequest {
  AfterUpdateExtensionRequest({required this.collection, required this.before, required this.after, required super.jwt})
    : assert(before.length == after.length, 'Before and after must have the same length (${before.length} != ${after.length})'),
      super(path: _path, step: .afterSuccess, type: .update, id: Request.generateId());

  AfterUpdateExtensionRequest._({
    required super.id,
    required this.collection,
    required this.before,
    required this.after,
    required super.step,
    required super.jwt,
  }) : super(path: _path, type: .update);

  factory AfterUpdateExtensionRequest.fromRequest(UnknownRequest request) {
    return AfterUpdateExtensionRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      before: (request.payload['before'] as List).cast(),
      after: (request.payload['after'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.update.after_success';

  final String collection;
  final List<Map<String, dynamic>> before;
  final List<Map<String, dynamic>> after;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'collection': collection, 'before': before, 'after': after};
  }
}
