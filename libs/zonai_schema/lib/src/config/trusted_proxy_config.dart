/// Trusted reverse-proxy headers for resolving the client IP address.
///
/// Serialized in the config worker and mapped to [TrustedProxy] on the server.
final class TrustedProxyConfig {
  const TrustedProxyConfig({
    this.headers = const [],
    this.useLeftmostIp = false,
  });

  factory TrustedProxyConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TrustedProxyConfig();
    return TrustedProxyConfig(
      headers: _stringList(json['headers']),
      useLeftmostIp: json['useLeftmostIp'] as bool? ?? false,
    );
  }

  /// Header names to check in order (e.g. `X-Forwarded-For`, `CF-Connecting-IP`).
  final List<String> headers;

  /// When `true`, use the leftmost valid IP in each header value.
  ///
  /// When `false` (default), use the rightmost valid IP — the value appended
  /// by your trusted proxy.
  final bool useLeftmostIp;

  Map<String, dynamic> toJson() => {
    'headers': headers,
    'useLeftmostIp': useLeftmostIp,
  };

  static List<String> _stringList(Object? value) {
    if (value == null) return const [];
    if (value is! List<dynamic>) {
      throw ArgumentError.value(
        value,
        'headers',
        'expected a JSON array of strings',
      );
    }
    return value.map((e) => e as String).toList();
  }
}
