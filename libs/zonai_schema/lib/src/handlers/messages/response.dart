part of 'message_handler.dart';

sealed class Response {
  const Response();

  factory Response.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid received message path: ${json['path']}');
    }

    return switch (path) {
      ResponsePing._path => ResponsePing.fromJson(json),
      ResponseKill._path => ResponseKill.fromJson(json),
      _ => throw ArgumentError('Invalid received message path: $path'),
    };
  }

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path};
  }

  String get path;
}

class ResponsePing extends Response {
  const ResponsePing();

  factory ResponsePing.fromJson(Map<String, dynamic> json) {
    return ResponsePing();
  }

  static const _path = 'ping';

  @override
  String get path => _path;
}

class ResponseKill extends Response {
  const ResponseKill();

  factory ResponseKill.fromJson(Map<String, dynamic> json) {
    return ResponseKill();
  }

  static const _path = 'kill';

  @override
  String get path => _path;
}
