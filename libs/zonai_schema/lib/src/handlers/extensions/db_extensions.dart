import 'package:zonai_schema/src/extension.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/table_extensions.dart';

class DbExtensions {
  DbExtensions({required this.extensions});

  final List<Extension> extensions;

  Map<String, Extension>? _extensionsByCollection;
  Map<String, Extension> get extensionsByCollection {
    return _extensionsByCollection ??= {
      for (final extension in this.extensions) extension.table.name: extension,
    };
  }

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        ExtensionRequest request;
        try {
          request = ExtensionRequest.fromRequest(msg);
        } catch (e, stack) {
          logger.error(
            'Error handling extension request',
            error: '$e',
            stackTrace: stack.toString(),
            properties: {'request': msg.toJson()},
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
    final extension = extensionsByCollection[request.collection];
    if (extension == null) {
      return;
    }
    dynamic object(Map<String, dynamic> object) {
      return extension.table.safeCreate(object);
    }

    switch (request.step) {
      case .before:
        if (extension case DeleteExtension(:final beforeDelete)) {
          for (final o in request.objects) {
            await beforeDelete(object(o));
          }
        }
      case .afterSuccess:
        if (extension case DeleteExtension(:final afterDeleteSuccess)) {
          for (final o in request.objects) {
            await afterDeleteSuccess(object(o));
          }
        }
      case .afterError:
        throw StateError('After error step should not be handled here');
    }
  }

  Future<void> _beforeUpdate(BeforeUpdateExtensionRequest request) async {
    final extension = extensionsByCollection[request.collection];
    if (extension == null) {
      return;
    }

    dynamic object(Map<String, dynamic> object) {
      return extension.table.safeCreate(object);
    }

    if (extension case UpdateExtension(:final beforeUpdate)) {
      for (final o in request.objects) {
        await beforeUpdate(object(o));
      }
    }
  }

  Future<void> _afterUpdate(AfterUpdateExtensionRequest request) async {
    final extension = extensionsByCollection[request.collection];
    if (extension == null) {
      return;
    }

    dynamic object(Map<String, dynamic> object) {
      return extension.table.safeCreate(object);
    }

    if (extension case UpdateExtension(:final afterUpdateSuccess)) {
      for (var i = 0; i < request.before.length; i++) {
        final before = request.before[i];
        final after = request.after[i];

        await afterUpdateSuccess(object(before), object(after));
      }
    }
  }

  Future<void> _create(CreateExtensionRequest request) async {
    final extension = extensionsByCollection[request.collection];
    if (extension == null) {
      return;
    }
    dynamic object() => extension.table.safeCreate(request.object);

    switch (request.step) {
      case .before:
        if (extension case CreateExtension(:final beforeCreate)) {
          await beforeCreate(object());
        }
      case .afterSuccess:
        if (extension case CreateExtension(:final afterCreateSuccess)) {
          await afterCreateSuccess(object());
        }
      case .afterError:
        throw StateError('After error step should not be handled here');
    }
  }

  Future<void> _error(ErrorExtensionRequest request) async {
    final extension = extensionsByCollection[request.collection];

    switch (request.type) {
      case .create:
        if (extension case CreateExtension(:final afterCreateError)) {
          await afterCreateError(request.error);
        }
      case .update:
        if (extension case UpdateExtension(:final afterUpdateError)) {
          await afterUpdateError(request.error);
        }
      case .delete:
        if (extension case DeleteExtension(:final afterDeleteError)) {
          await afterDeleteError(request.error);
        }
    }
  }

  Future<void> _auth(AuthExtensionRequest request) async {
    final extension = extensionsByCollection[request.collection];
    if (extension == null) {
      return;
    }

    switch (request.step) {
      case .onSignUp:
        if (extension case AuthExtension(:final onSignUp)) {
          await onSignUp(extension.table.safeCreate(request.object));
        }
      case .onSignIn:
        if (extension case AuthExtension(:final onSignIn)) {
          await onSignIn(extension.table.safeCreate(request.object));
        }
    }
  }
}
