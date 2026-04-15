part of 'message_handler.dart';

sealed class Request {
  const Request();

  factory Request.fromJson(Map<String, dynamic> json) {
    final path = json['path'];

    if (path == null) {
      throw ArgumentError('Invalid send message path: ${json['path']}');
    }

    return switch (path) {
      SendMessageDebug._path => SendMessageDebug.fromJson(json),
      _ => throw ArgumentError('Invalid send message path: $path'),
    };
  }

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path};
  }

  String get path;
}

class SendMessageDebug extends Request {
  const SendMessageDebug({required this.message});

  factory SendMessageDebug.fromJson(Map<String, dynamic> json) {
    return SendMessageDebug(message: json['message']);
  }

  static const _path = 'debug';

  @override
  String get path => _path;

  final String message;

  @override
  Map<String, dynamic> toJson() => {'message': message, ...super.toJson()};
}
