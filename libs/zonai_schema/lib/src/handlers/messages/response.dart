part of 'message_handler.dart';

base class Response {
  const Response({required this.path, required this.id, required this.payload});

  factory Response.fromJson(Map<String, dynamic> json) {
    final path = json['path'];

    if (path == null) {
      throw ArgumentError('Invalid send message path: ${json['path']}');
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid send message id: ${json['id']}');
    }

    return switch (path) {
      DebugResponse._path => DebugResponse.fromJson(json),
      _ => Response(path: path, id: id, payload: json),
    };
  }

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path};
  }

  final String path;
  final String id;
  final Map<String, dynamic> payload;
}

final class DebugResponse extends Response {
  DebugResponse({required this.message})
    : super(path: _path, id: '-1', payload: {'message': message});

  factory DebugResponse.fromJson(Map<String, dynamic> json) {
    return DebugResponse(message: json['message']);
  }

  static const _path = 'debug';

  @override
  String get path => _path;

  final String message;

  @override
  Map<String, dynamic> toJson() => {'message': message, ...super.toJson()};
}
