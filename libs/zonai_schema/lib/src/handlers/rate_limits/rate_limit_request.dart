import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/rate_limit_operation.dart';

final class RateLimitRequest extends Request {
  RateLimitRequest({required this.collection, required this.operation})
    : super(id: Request.generateId(), path: _path);

  RateLimitRequest._({
    required super.id,
    required this.collection,
    required this.operation,
  }) : super(path: _path);

  factory RateLimitRequest.fromRequest(UnknownRequest request) {
    return RateLimitRequest._(
      id: request.id,
      collection: request.payload['collection'] as String,
      operation: RateLimitOperation.values.byName(
        request.payload['operation'] as String,
      ),
    );
  }

  factory RateLimitRequest.fromJson(Map<String, dynamic> json) {
    return RateLimitRequest._(
      id: json['id'] as String,
      collection: json['collection'] as String,
      operation: RateLimitOperation.values.byName(json['operation'] as String),
    );
  }

  final String collection;
  final RateLimitOperation operation;

  static const _path = '${Request.prefix}.rate_limit';

  @override
  String get path => _path;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'collection': collection,
      'operation': operation.name,
    };
  }
}
