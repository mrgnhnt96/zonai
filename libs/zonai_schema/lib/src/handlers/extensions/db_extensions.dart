import 'package:zonai_schema/src/extension.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/table_extensions.dart';

class DbExtensions {
  DbExtensions({required this.extensions});

  final List<Extension> extensions;

  Map<String, Extension>? _extensionsByTable;
  Map<String, Extension> get extensionsByTable {
    if (_extensionsByTable case final map?) return map;

    final map = <String, Extension>{};
    for (final extension in this.extensions) {
      if (map[extension.table.name] != null) {
        throw StateError(
          'Extensions already registered for ${extension.table.name}. '
          'Existing extensions: ${map[extension.table.name]?.runtimeType}, tried to register ${extension.runtimeType}',
        );
      }
    }

    return _extensionsByTable = map;
  }

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        ExtensionRequest request;
        try {
          request = ExtensionRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.debug(
            'Error handling request',
            properties: {'request': msg.toJson(), 'error': e.toString()},
          );
          return MessageErrorResponse(
            id: msg.id,
            message: 'Error handling extension request',
            error: e.toString(),
            stackTrace: stack.toString(),
          );
        }

        switch (request) {
          case final CreateExtensionRequest request:
            await _create(request);
            return NoActionExtensionResponse(id: request.id);

          case final BeforeUpdateExtensionRequest request:
            await _beforeUpdate(request);
            return NoActionExtensionResponse(id: request.id);

          case final AfterUpdateExtensionRequest request:
            await _afterUpdate(request);
            return NoActionExtensionResponse(id: request.id);

          case final DeleteExtensionRequest request:
            await _delete(request);
            return NoActionExtensionResponse(id: request.id);

          case final ErrorExtensionRequest request:
            await _error(request);
            return NoActionExtensionResponse(id: request.id);

          case final AuthExtensionRequest request:
            await _auth(request);
            return NoActionExtensionResponse(id: request.id);
        }
      },
    ).listen();
  }

  Future<void> _delete(DeleteExtensionRequest request) async {
    final extension = extensionsByTable[request.table];
    if (extension == null) {
      return;
    }
    dynamic object(Map<String, dynamic> object) {
      return extension.table.safeCreate(object);
    }

    switch (request.step) {
      case .before:
        if (extension case Extension(:final beforeDelete)) {
          for (final o in request.objects) {
            await beforeDelete(object(o), request.jwt);
          }
        }
      case .afterSuccess:
        if (extension case Extension(:final afterDeleteSuccess)) {
          for (final o in request.objects) {
            await afterDeleteSuccess(object(o), request.jwt);
          }
        }
      case .afterError:
        throw StateError('After error step should not be handled here');
    }
  }

  Future<void> _beforeUpdate(BeforeUpdateExtensionRequest request) async {
    final extension = extensionsByTable[request.table];
    if (extension == null) {
      return;
    }

    dynamic object(Map<String, dynamic> object) {
      return extension.table.safeCreate(object);
    }

    if (extension case Extension(:final beforeUpdate)) {
      for (final o in request.objects) {
        await beforeUpdate(object(o), request.jwt);
      }
    }
  }

  Future<void> _afterUpdate(AfterUpdateExtensionRequest request) async {
    final extension = extensionsByTable[request.table];
    if (extension == null) {
      return;
    }

    dynamic object(Map<String, dynamic> object) {
      return extension.table.safeCreate(object);
    }

    if (extension case Extension(:final afterUpdateSuccess)) {
      for (var i = 0; i < request.before.length; i++) {
        final before = request.before[i];
        final after = request.after[i];

        await afterUpdateSuccess(object(before), object(after), request.jwt);
      }
    }
  }

  Future<void> _create(CreateExtensionRequest request) async {
    final extension = extensionsByTable[request.table];
    if (extension == null) {
      return;
    }
    dynamic object() => extension.table.safeCreate(request.object);

    switch (request.step) {
      case .before:
        if (extension case Extension(:final beforeCreate)) {
          await beforeCreate(object(), request.jwt);
        }
      case .afterSuccess:
        if (extension case Extension(:final afterCreateSuccess)) {
          await afterCreateSuccess(object(), request.jwt);
        }
      case .afterError:
        throw StateError('After error step should not be handled here');
    }
  }

  Future<void> _error(ErrorExtensionRequest request) async {
    final extension = extensionsByTable[request.table];

    switch (request.type) {
      case .create:
        if (extension case Extension(:final afterCreateError)) {
          await afterCreateError(request.error, request.jwt);
        }
      case .update:
        if (extension case Extension(:final afterUpdateError)) {
          await afterUpdateError(request.error, request.jwt);
        }
      case .delete:
        if (extension case Extension(:final afterDeleteError)) {
          await afterDeleteError(request.error, request.jwt);
        }
    }
  }

  Future<void> _auth(AuthExtensionRequest request) async {
    final extension = extensionsByTable[request.table];
    if (extension == null) {
      return;
    }

    switch (request.step) {
      case .onSignUp:
        if (extension case AuthExtension(:final onSignUp)) {
          await onSignUp(
            extension.table.safeCreate(request.object),
            request.jwt,
          );
        }
      case .onSignIn:
        if (extension case AuthExtension(:final onSignIn)) {
          await onSignIn(
            extension.table.safeCreate(request.object),
            request.jwt,
          );
        }
      case .onRefresh:
        if (extension case AuthExtension(:final onRefresh)) {
          await onRefresh(
            extension.table.safeCreate(request.object),
            request.jwt,
          );
        }
      case .onLogout:
        if (extension case AuthExtension(:final onLogout)) {
          await onLogout(
            extension.table.safeCreate(request.object),
            request.jwt,
          );
        }
      case .onPasswordReset:
        if (extension case AuthExtension(:final onPasswordReset)) {
          await onPasswordReset(
            extension.table.safeCreate(request.object),
            request.jwt,
          );
        }
    }
  }
}
