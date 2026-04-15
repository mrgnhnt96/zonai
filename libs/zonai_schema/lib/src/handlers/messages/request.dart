part of 'message_handler.dart';

base class Request {
  const Request({required this.payload, required this.path, required this.id});

  factory Request.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid received message path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid received message id: ${json['id']}');
    }

    return switch (path) {
      RequestPing._path => RequestPing.fromJson(json),
      RequestKill._path => RequestKill.fromJson(json),
      _ => Request(payload: json, path: path, id: id),
    };
  }

  static String generateId() {
    return sha256
        .convert(utf8.encode(DateTime.now().toIso8601String()))
        .toString()
        .substring(0, 15);
  }

  final Map<String, dynamic> payload;
  final String path;
  final String id;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path, 'id': id};
  }
}

final class RequestPing extends Request {
  RequestPing()
    : super(payload: const {}, path: _path, id: Request.generateId());

  factory RequestPing.fromJson(Map<String, dynamic> json) {
    return RequestPing();
  }

  static const _path = 'ping';

  @override
  String get path => _path;
}

final class RequestKill extends Request {
  RequestKill()
    : super(payload: const {}, path: _path, id: Request.generateId());

  factory RequestKill.fromJson(Map<String, dynamic> json) {
    return RequestKill();
  }

  static const _path = 'kill';

  @override
  String get path => _path;
}
