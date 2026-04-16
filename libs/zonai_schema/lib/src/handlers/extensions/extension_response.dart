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

    throw UnimplementedError();
  }
}
