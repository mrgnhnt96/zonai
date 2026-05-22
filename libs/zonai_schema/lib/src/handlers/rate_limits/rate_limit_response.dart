import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

final class RateLimitResponse extends Response {
  RateLimitResponse({required this.policy, required super.id})
    : super(path: _path, payload: {});

  factory RateLimitResponse.fromJson(Map<String, dynamic> json) {
    final policyJson = json['policy'];
    return RateLimitResponse(
      policy: policyJson == null
          ? null
          : RateLimitPolicy.fromJson(policyJson as Map<String, dynamic>),
      id: json['id'] as String,
    );
  }

  final RateLimitPolicy? policy;

  static const _path = '${Response.prefix}.rate_limit';

  @override
  String get path => _path;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      if (policy != null) 'policy': policy!.toJson(),
    };
  }
}
