part of 'message_handler.dart';

abstract base class Request {
  const Request({required this.path, required this.id});

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
      _ => UnknownRequest(path: path, id: id, payload: json),
    };
  }

  static String generateId() {
    return sha256
        .convert(utf8.encode(DateTime.now().toIso8601String()))
        .toString()
        .substring(0, 15);
  }

  final String path;
  final String id;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path, 'id': id};
  }
}

final class UnknownRequest extends Request {
  UnknownRequest({
    required this.payload,
    required super.path,
    required super.id,
  });

  final Map<String, dynamic> payload;
}

final class RequestPing extends Request {
  RequestPing() : super(path: _path, id: Request.generateId());
  const RequestPing._({required super.id}) : super(path: _path);

  factory RequestPing.fromJson(Map<String, dynamic> json) {
    return RequestPing._(id: json['id'] as String);
  }

  static const _path = 'ping';

  @override
  String get path => _path;
}

final class RequestKill extends Request {
  RequestKill() : super(path: _path, id: Request.generateId());

  factory RequestKill.fromJson(Map<String, dynamic> json) {
    return RequestKill();
  }

  static const _path = 'kill';

  @override
  String get path => _path;
}
