import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

final class RateLimitResponse extends Response {
  RateLimitResponse({
    required this.policy,
    required super.id,
    this.counters = const {},
    this.key,
  }) : super(path: _path, payload: {});

  factory RateLimitResponse.fromJson(Map<String, dynamic> json) {
    final policyJson = json['policy'];
    final countersJson = json['counters'] as Map<String, dynamic>?;
    return RateLimitResponse(
      policy: policyJson == null
          ? null
          : RateLimitPolicy.fromJson(policyJson as Map<String, dynamic>),
      id: json['id'] as String,
      counters: {
        if (countersJson != null)
          for (final MapEntry(:key, :value) in countersJson.entries)
            key: value as String,
      },
      key: json['key'] as String?,
    );
  }

  final RateLimitPolicy? policy;

  /// For a create's policy: the table's keyed counters, counter name to the
  /// name of the column whose value keys it. Empty for every other request.
  final Map<String, String> counters;

  /// For a counter's policy: the key the create is counted under, or `null`
  /// when it is counted on the caller's IP address instead.
  final String? key;

  static const _path = '${Response.prefix}.rate_limit';

  @override
  String get path => _path;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      if (policy != null) 'policy': policy!.toJson(),
      if (counters.isNotEmpty) 'counters': counters,
      if (key != null) 'key': key,
    };
  }
}
