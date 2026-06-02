import 'package:revali_router_core/revali_router_core.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/config/trusted_proxy_config.dart';

TrustedProxy _toTrustedProxy(TrustedProxyConfig config) =>
    TrustedProxy(headers: config.headers, useLeftmostIp: config.useLeftmostIp);

final class _TestHeaders implements Headers {
  _TestHeaders(this._values);

  final Map<String, List<String>> _values;

  @override
  String? get(String key) => getAll(key)?.lastOrNull;

  @override
  List<String>? getAll(String key) {
    final normalized = key.toLowerCase();
    for (final entry in _values.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    return null;
  }

  @override
  Map<String, List<String>> get values => _values;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('resolveClientIp with TrustedProxyConfig', () {
    const remote = '10.0.0.1';

    test('returns remote IP when trusted proxy headers are not configured', () {
      expect(
        resolveClientIp(
          remoteIp: remote,
          headers: _TestHeaders({
            'x-forwarded-for': ['203.0.113.1, 198.51.100.178'],
          }),
          trustedProxy: _toTrustedProxy(const TrustedProxyConfig()),
        ),
        remote,
      );
    });

    test('uses rightmost valid IP by default', () {
      expect(
        resolveClientIp(
          remoteIp: remote,
          headers: _TestHeaders({
            'x-forwarded-for': ['203.0.113.1, 198.51.100.178'],
          }),
          trustedProxy: _toTrustedProxy(
            const TrustedProxyConfig(headers: ['X-Forwarded-For']),
          ),
        ),
        '198.51.100.178',
      );
    });

    test('uses leftmost valid IP when useLeftmostIp is true', () {
      expect(
        resolveClientIp(
          remoteIp: remote,
          headers: _TestHeaders({
            'x-forwarded-for': ['203.0.113.1, 198.51.100.178'],
          }),
          trustedProxy: _toTrustedProxy(
            const TrustedProxyConfig(
              headers: ['X-Forwarded-For'],
              useLeftmostIp: true,
            ),
          ),
        ),
        '203.0.113.1',
      );
    });
  });
}
