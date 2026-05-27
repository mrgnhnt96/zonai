import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/rate_limit_operation.dart';

final class RateLimitRequest extends Request {
  RateLimitRequest({required this.table, required this.operation})
    : super(id: Request.generateId(), path: _path);

  RateLimitRequest._({
    required super.id,
    required this.table,
    required this.operation,
  }) : super(path: _path);

  factory RateLimitRequest.fromRequest(UnknownRequest request) {
    return RateLimitRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: RateLimitOperation.values.byName(
        request.payload['operation'] as String,
      ),
    );
  }

  factory RateLimitRequest.fromJson(Map<String, dynamic> json) {
    return RateLimitRequest._(
      id: json['id'] as String,
      table: json['table'] as String,
      operation: RateLimitOperation.values.byName(json['operation'] as String),
    );
  }

  final String table;
  final RateLimitOperation operation;

  static const _path = '${Request.prefix}.rate_limit';

  @override
  String get path => _path;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation.name,
    };
  }
}
