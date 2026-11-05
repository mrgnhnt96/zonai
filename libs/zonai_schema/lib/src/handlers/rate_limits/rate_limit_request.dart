import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/rate_limit_operation.dart';

final class RateLimitRequest extends Request {
  RateLimitRequest({
    required this.table,
    required this.operation,
    this.customOperation,
    this.counter,
    this.value,
  }) : super(id: Request.generateId(), path: _path);

  RateLimitRequest._({
    required super.id,
    required this.table,
    required this.operation,
    this.customOperation,
    this.counter,
    this.value,
  }) : super(path: _path);

  factory RateLimitRequest.fromRequest(UnknownRequest request) {
    return RateLimitRequest._(
      id: request.id,
      table: request.payload['table'] as String,
      operation: RateLimitOperation.values.byName(
        request.payload['operation'] as String,
      ),
      customOperation: request.payload['customOperation'] as String?,
      counter: request.payload['counter'] as String?,
      value: request.payload['value'] as String?,
    );
  }

  factory RateLimitRequest.fromJson(Map<String, dynamic> json) {
    return RateLimitRequest._(
      id: json['id'] as String,
      table: json['table'] as String,
      operation: RateLimitOperation.values.byName(json['operation'] as String),
      customOperation: json['customOperation'] as String?,
      counter: json['counter'] as String?,
      value: json['value'] as String?,
    );
  }

  final String table;
  final RateLimitOperation operation;

  /// The custom operation name, present only when [operation] is
  /// [RateLimitOperation.custom].
  final String? customOperation;

  /// The name of one of the table's `createCounters`, when the host is asking
  /// for that counter's key and policy rather than for the per-IP policy.
  final String? counter;

  /// The value of [counter]'s column in the submitted row, or `null` when the
  /// row had no usable value for it.
  final String? value;

  static const _path = '${Request.prefix}.rate_limit';

  @override
  String get path => _path;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'table': table,
      'operation': operation.name,
      'customOperation': customOperation,
      if (counter != null) 'counter': counter,
      if (value != null) 'value': value,
    };
  }
}
