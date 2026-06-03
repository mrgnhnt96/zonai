import 'package:revali_router_core/method_mutations/headers/headers.dart';
import 'package:revali_router_core/trusted_proxy/trusted_proxy.dart';
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
  group('TrustedProxy.resolve with TrustedProxyConfig', () {
    const remote = '10.0.0.1';

    test('returns remote IP when trusted proxy headers are not configured', () {
      expect(
        _toTrustedProxy(const TrustedProxyConfig()).resolve(
          remote,
          _TestHeaders({
            'x-forwarded-for': ['203.0.113.1, 198.51.100.178'],
          }),
        ),
        remote,
      );
    });

    test('uses rightmost valid IP by default', () {
      expect(
        _toTrustedProxy(
          const TrustedProxyConfig(headers: ['X-Forwarded-For']),
        ).resolve(
          remote,
          _TestHeaders({
            'x-forwarded-for': ['203.0.113.1, 198.51.100.178'],
          }),
        ),
        '198.51.100.178',
      );
    });

    test('uses leftmost valid IP when useLeftmostIp is true', () {
      expect(
        _toTrustedProxy(
          const TrustedProxyConfig(
            headers: ['X-Forwarded-For'],
            useLeftmostIp: true,
          ),
        ).resolve(
          remote,
          _TestHeaders({
            'x-forwarded-for': ['203.0.113.1, 198.51.100.178'],
          }),
        ),
        '203.0.113.1',
      );
    });
  });
}
