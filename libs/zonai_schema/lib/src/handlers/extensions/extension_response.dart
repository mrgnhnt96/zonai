import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

sealed class ExtensionResponse extends Response {
  const ExtensionResponse({
    required super.path,
    required super.id,
    required super.payload,
  });

  factory ExtensionResponse.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid extension response path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid extension response id: ${json['id']}');
    }

    return switch (path) {
      NoActionExtensionResponse._path => NoActionExtensionResponse.fromJson(
        json,
      ),
      BeforeCreateExtensionResponse._path =>
        BeforeCreateExtensionResponse.fromJson(json),
      _ => throw ArgumentError('Invalid extension response path: $path'),
    };
  }
}

final class NoActionExtensionResponse extends ExtensionResponse {
  NoActionExtensionResponse({required super.id})
    : super(path: _path, payload: {});

  factory NoActionExtensionResponse.fromJson(Map<String, dynamic> json) {
    return NoActionExtensionResponse(id: json['id']);
  }

  static const _path = 'extension.no_action';
}

final class BeforeCreateExtensionResponse extends ExtensionResponse {
  BeforeCreateExtensionResponse({required super.id})
    : super(path: _path, payload: {});

  factory BeforeCreateExtensionResponse.fromJson(Map<String, dynamic> json) {
    return BeforeCreateExtensionResponse(id: json['id']);
  }

  static const _path = 'extension.before_create';
}
