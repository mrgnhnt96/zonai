// dart format width=150
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/push_outcome.dart';

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
      BeforeSignUpExtensionRequest._path => BeforeSignUpExtensionRequest.fromRequest(request),
      PushRejectedExtensionRequest._path => PushRejectedExtensionRequest.fromRequest(request),
      _ => throw ArgumentError('Invalid extension request path: ${request.path}'),
    };
  }
}

enum ExtensionStep { before, afterSuccess, afterError }

enum ExtensionType { create, update, delete }

enum AuthExtensionStep { onSignUp, onSignIn, onRefresh, onLogout, onPasswordReset, onExternalAuthFirstSeen }

/// The one extension request dispatched BEFORE its auth flow commits anything,
/// and the only one whose reply can change the outcome.
///
/// It carries the sign-up body rather than a row, because at this point there
/// is no row -- see [SignUpCandidate] for why fabricating one does not work.
/// Throwing `SignUpDeclinedException` from the hook is what refuses the
/// sign-up; the host recovers it from the error text on the far side.
final class BeforeSignUpExtensionRequest extends ExtensionRequest {
  BeforeSignUpExtensionRequest({required this.table, required this.email, required this.object, required super.jwt})
    : super(path: _path, id: Request.generateId());

  BeforeSignUpExtensionRequest._({required super.id, required this.table, required this.email, required this.object, required super.jwt})
    : super(path: _path);

  factory BeforeSignUpExtensionRequest.fromRequest(UnknownRequest request) {
    return BeforeSignUpExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      email: request.payload['email'] as String,
      object: Map<String, dynamic>.from(request.payload['object'] as Map? ?? const {}),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.before_sign_up';

  final String table;
  final String email;
  final Map<String, dynamic> object;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'email': email, 'object': object};
  }
}

/// The [jwt] belongs to the user who is making the request, not the user that is being created or signed in.
final class AuthExtensionRequest extends ExtensionRequest {
  AuthExtensionRequest.onSignUp({required this.table, required this.object, required super.jwt})
    : step = .onSignUp,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onSignIn({required this.table, required this.object, required super.jwt})
    : step = .onSignIn,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onRefresh({required this.table, required this.object, required super.jwt})
    : step = .onRefresh,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onLogout({required this.table, required this.object, required super.jwt})
    : step = .onLogout,
      super(path: _path, id: Request.generateId());
  AuthExtensionRequest.onPasswordReset({required this.table, required this.object, required super.jwt})
    : step = .onPasswordReset,
      super(path: _path, id: Request.generateId());

  /// Invoked when an external IdP token's `sub` does not match any
  /// existing row in [table]. The hook may insert the missing row
  /// (via the `mutate` API) so the auth flow can resolve `Jwt.user`
  /// and proceed. [object] carries the verified IdP claims map.
  AuthExtensionRequest.onExternalAuthFirstSeen({required this.table, required this.object, required super.jwt})
    : step = .onExternalAuthFirstSeen,
      super(path: _path, id: Request.generateId());

  AuthExtensionRequest._({required super.id, required this.table, required this.object, required this.step, required super.jwt}) : super(path: _path);

  factory AuthExtensionRequest.fromRequest(UnknownRequest request) {
    return AuthExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      object: request.payload['object'] as Map<String, dynamic>,
      step: AuthExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.auth';

  final String table;
  final Map<String, dynamic> object;
  final AuthExtensionStep step;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'object': object, 'step': step.name};
  }
}

/// Tells the app that FCM has permanently rejected [token], **before** Zonai
/// prunes it.
///
/// Before, not after, so [object] is still the intact row when the app sees
/// it — a hook handed a row Zonai had already cleared could not tell which
/// user it belonged to. It is dispatched under all three
/// `OnPermanentRejection` settings, including `none`; that is what makes
/// `none` a usable choice rather than a silent one.
final class PushRejectedExtensionRequest extends ExtensionRequest {
  PushRejectedExtensionRequest({required this.table, required this.object, required this.token, required this.reason, required super.jwt})
    : super(path: _path, id: Request.generateId());

  PushRejectedExtensionRequest._({
    required super.id,
    required this.table,
    required this.object,
    required this.token,
    required this.reason,
    required super.jwt,
  }) : super(path: _path);

  factory PushRejectedExtensionRequest.fromRequest(UnknownRequest request) {
    return PushRejectedExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      object: Map<String, dynamic>.from(request.payload['object'] as Map),
      token: request.payload['token'] as String,
      reason: PushRejectionReason.fromJson(request.payload['reason'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.push_rejected';

  final String table;
  final Map<String, dynamic> object;
  final String token;
  final PushRejectionReason reason;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'object': object, 'token': token, 'reason': reason.toJson()};
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
  ErrorExtensionRequest.create({required this.table, required this.error, required super.jwt})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .create);
  ErrorExtensionRequest.update({required this.table, required this.error, required super.jwt})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .update);
  ErrorExtensionRequest.delete({required this.table, required this.error, required super.jwt})
    : super(id: Request.generateId(), path: _path, step: .afterError, type: .delete);

  ErrorExtensionRequest._({required super.id, required this.table, required this.error, required super.step, required super.type, required super.jwt})
    : super(path: _path);

  factory ErrorExtensionRequest.fromRequest(UnknownRequest request) {
    return ErrorExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      error: request.payload['error'] as String,
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      type: ExtensionType.values.byName(request.payload['type'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.error';

  final String table;
  final String error;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'error': error};
  }
}

final class CreateExtensionRequest extends RecordExtensionRequest {
  CreateExtensionRequest.before({required this.table, required this.object, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .before, type: .create);
  CreateExtensionRequest.afterSuccess({required this.table, required this.object, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .afterSuccess, type: .create);

  CreateExtensionRequest._({required super.id, required this.table, required this.object, required super.step, required super.jwt})
    : super(path: _path, type: .create);

  factory CreateExtensionRequest.fromRequest(UnknownRequest request) {
    return CreateExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      object: request.payload['object'] as Map<String, dynamic>,
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.create';

  final String table;
  final Map<String, dynamic> object;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'object': object};
  }
}

final class DeleteExtensionRequest extends RecordExtensionRequest {
  DeleteExtensionRequest.before({required this.table, required this.objects, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .before, type: .create);
  DeleteExtensionRequest.afterSuccess({required this.table, required this.objects, required super.jwt})
    : super(path: _path, id: Request.generateId(), step: .afterSuccess, type: .create);

  DeleteExtensionRequest._({required super.id, required this.table, required this.objects, required super.step, required super.jwt})
    : super(path: _path, type: .create);

  factory DeleteExtensionRequest.fromRequest(UnknownRequest request) {
    return DeleteExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      objects: (request.payload['object'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.delete';

  final String table;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'object': objects};
  }
}

final class BeforeUpdateExtensionRequest extends RecordExtensionRequest {
  BeforeUpdateExtensionRequest({required this.table, required this.objects, required super.jwt})
    : super(path: _path, step: .before, type: .update, id: Request.generateId());

  BeforeUpdateExtensionRequest._({required super.id, required this.table, required this.objects, required super.step, required super.jwt})
    : super(path: _path, type: .update);

  factory BeforeUpdateExtensionRequest.fromRequest(UnknownRequest request) {
    return BeforeUpdateExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      objects: (request.payload['object'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.update.before';

  final String table;
  final List<Map<String, dynamic>> objects;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'object': objects};
  }
}

final class AfterUpdateExtensionRequest extends RecordExtensionRequest {
  AfterUpdateExtensionRequest({required this.table, required this.before, required this.after, required super.jwt})
    : assert(before.length == after.length, 'Before and after must have the same length (${before.length} != ${after.length})'),
      super(path: _path, step: .afterSuccess, type: .update, id: Request.generateId());

  AfterUpdateExtensionRequest._({
    required super.id,
    required this.table,
    required this.before,
    required this.after,
    required super.step,
    required super.jwt,
  }) : super(path: _path, type: .update);

  factory AfterUpdateExtensionRequest.fromRequest(UnknownRequest request) {
    return AfterUpdateExtensionRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      before: (request.payload['before'] as List).cast(),
      after: (request.payload['after'] as List).cast(),
      step: ExtensionStep.values.byName(request.payload['step'] as String),
      jwt: request.jwt,
    );
  }

  static const _path = '${Request.prefix}.extension.update.after_success';

  final String table;
  final List<Map<String, dynamic>> before;
  final List<Map<String, dynamic>> after;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'table': table, 'before': before, 'after': after};
  }
}
