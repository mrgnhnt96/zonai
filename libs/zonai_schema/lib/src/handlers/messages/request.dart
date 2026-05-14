part of 'message_handler.dart';

abstract base class Request {
  const Request({required this.path, required this.id, this.jwt});

  factory Request.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path == null) {
      throw ArgumentError('Invalid request path: ${json['path']}');
    }

    if (!path.startsWith(prefix)) {
      throw ArgumentError(
        'Invalid request path: $path, should start with $prefix',
      );
    }

    final id = json['id'];
    if (id == null) {
      throw ArgumentError('Invalid request id: ${json['id']}');
    }

    return switch (path) {
      RequestPing._path => RequestPing.fromJson(json),
      RequestKill._path => RequestKill.fromJson(json),
      GetRecordRequest._path => GetRecordRequest.fromJson(json),
      _ => UnknownRequest(
        path: path,
        id: id,
        payload: json,
        jwt: Jwt.maybeFromJson(json['jwt']),
      ),
    };
  }

  static const prefix = 'request/';

  static int _generateSeq = 0;

  /// Generates a unique ID for a request: time + seq + entropy (avoids same-ms collisions).
  static String generateId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final seq = _generateSeq = (_generateSeq + 1) & 0x3fffffff;
    final r = Random.secure().nextInt(0x40000000);
    return sha256.convert(utf8.encode('$t:$seq:$r')).toString();
  }

  final String path;
  final String id;
  final Jwt? jwt;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'path': path, 'id': id, 'jwt': ?jwt?.toJson()};
  }
}

final class UnknownRequest extends Request {
  UnknownRequest({
    required this.payload,
    required super.path,
    required super.id,
    super.jwt,
  });

  final Map<String, dynamic> payload;
}

final class RequestPing extends Request {
  RequestPing() : super(path: _path, id: Request.generateId());
  RequestPing._({required super.id}) : super(path: _path);

  factory RequestPing.fromJson(Map<String, dynamic> json) {
    return RequestPing._(id: json['id'] as String);
  }

  static const _path = '${Request.prefix}.ping';

  @override
  String get path => _path;
}

final class RequestKill extends Request {
  RequestKill() : super(path: _path, id: Request.generateId());

  factory RequestKill.fromJson(Map<String, dynamic> json) {
    return RequestKill();
  }

  static const _path = '${Request.prefix}.kill';

  @override
  String get path => _path;
}

final class GetRecordRequest extends Request {
  GetRecordRequest({
    required this.collection,
    required this.where,
    this.limit,
    this.offset,
    super.jwt,
  }) : super(path: _path, id: Request.generateId());

  GetRecordRequest._({
    required super.id,
    required this.collection,
    required this.where,
    this.limit,
    this.offset,
    super.jwt,
  }) : super(path: _path);

  factory GetRecordRequest.fromJson(Map<String, dynamic> json) {
    return GetRecordRequest._(
      id: json['id'] as String,
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      jwt: Jwt.maybeFromJson(json['jwt']),
    );
  }

  static const _path = '${Request.prefix}.get_record';

  final String collection;
  final Where where;
  final int? limit;
  final int? offset;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'where': where.toJson(),
      'limit': limit,
      'offset': offset,
    };
  }
}
