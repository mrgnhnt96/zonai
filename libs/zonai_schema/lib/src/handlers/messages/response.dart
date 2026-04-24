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
      PongResponse._path => PongResponse.fromJson(json),
      _ => Response(path: path, id: id, payload: json),
    };
  }

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path, 'id': id, 'payload': payload};
  }

  final String path;
  final String id;
  final Map<String, dynamic> payload;
}

final class PongResponse extends Response {
  PongResponse({required super.id}) : super(path: _path, payload: const {});

  factory PongResponse.fromJson(Map<String, dynamic> json) {
    return PongResponse(id: json['id']);
  }

  static const _path = 'pong';
}

enum DebugLevel { debug, info, warn, error }

final class DebugResponse extends Response {
  DebugResponse({
    required this.message,
    this.level = .debug,
    this.stackTrace,
    this.error,
    this.properties,
  }) : super(path: _path, id: '-1', payload: {'message': message});

  factory DebugResponse.fromJson(Map<String, dynamic> json) {
    return DebugResponse(
      message: json['message'],
      level: DebugLevel.values.byName(json['level']),
      properties: json['properties'],
      stackTrace: json['stackTrace'],
      error: json['error'],
    );
  }

  static const _path = 'debug';

  @override
  String get path => _path;

  final String message;
  final DebugLevel level;
  final String? stackTrace;
  final String? error;
  final Map<String, dynamic>? properties;

  @override
  Map<String, dynamic> toJson() => {
    'message': message,
    'level': level.name,
    'properties': properties,
    ...super.toJson(),
  };
}
