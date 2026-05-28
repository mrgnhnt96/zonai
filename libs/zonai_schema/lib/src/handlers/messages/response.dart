part of 'message_handler.dart';

base class Response {
  const Response({required this.path, required this.id, required this.payload});

  factory Response.fromJson(Map<String, dynamic> json) {
    final path = json['path'];

    if (path == null) {
      throw ArgumentError('Invalid response path: ${json['path']}');
    }

    if (!path.startsWith(prefix)) {
      throw ArgumentError(
        'Invalid response path: $path, should start with $prefix',
      );
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid response id: ${json['id']}');
    }

    return switch (path) {
      DebugResponse._path => DebugResponse.fromJson(json),
      PongResponse._path => PongResponse.fromJson(json),
      MessageErrorResponse._path => MessageErrorResponse.fromJson(json),
      GetRecordResponse._path => GetRecordResponse.fromJson(json),
      _ when path.startsWith(CronResponse.prefix) => CronResponse.fromJson(
        json,
      ),
      _ => Response(path: path, id: id, payload: json),
    };
  }

  static const prefix = 'response/';

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

  static const _path = '${Response.prefix}.pong';
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

  static const _path = '${Response.prefix}.debug';

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
    'stackTrace': stackTrace,
    'error': error,
    ...super.toJson(),
  };
}

/// Thrown in the parent process when a worker replies with [MessageErrorResponse].
class MessageHandlerFailedException implements Exception {
  MessageHandlerFailedException(
    this.message, {
    this.cause,
    this.causeStackTrace,
  });

  final String message;
  final String? cause;
  final String? causeStackTrace;

  @override
  String toString() {
    if (cause == null) {
      return message;
    }
    return '$message: $cause';
  }
}

/// Sent to the parent on failure so the [id] can match a pending [Completer].
final class MessageErrorResponse extends Response {
  MessageErrorResponse({
    required super.id,
    required this.message,
    this.error,
    this.stackTrace,
  }) : super(path: _path, payload: const {});

  factory MessageErrorResponse.fromJson(Map<String, dynamic> json) {
    return MessageErrorResponse(
      id: json['id'] as String,
      message: json['message'] as String,
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }

  static const _path = '${Response.prefix}.error';

  final String message;
  final String? error;
  final String? stackTrace;

  @override
  Map<String, dynamic> toJson() => {
    'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
    ...super.toJson(),
  };
}

final class GetRecordResponse extends Response {
  GetRecordResponse({required super.id, required this.records})
    : super(path: _path, payload: {'records': records});

  factory GetRecordResponse.fromJson(Map<String, dynamic> json) {
    return GetRecordResponse(
      id: json['id'],
      records: [
        for (final record in json['records'] as List<dynamic>)
          Map<String, Object?>.from(record),
      ],
    );
  }

  static const _path = '${Response.prefix}.get_record';

  final List<Map<String, Object?>> records;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'records': records};
}
