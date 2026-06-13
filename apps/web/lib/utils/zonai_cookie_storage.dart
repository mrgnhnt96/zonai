import 'package:revali_client/revali_client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

/// [Storage] adapter that persists the access token in the [ZonaiCookie.authToken] cookie.
///
/// Non-token keys (e.g. `__BASE_URL__` written by the generated [Server]) are kept
/// in memory only.
class ZonaiCookieStorage implements Storage {
  static const tokenKey = 'token';

  final Map<String, Object?> _memory = {};

  @override
  Future<Object?> operator [](String key) async {
    if (key == tokenKey) {
      return ZonaiCookie.authToken.read();
    }
    return _memory[key];
  }

  @override
  Future<void> clear() async {
    _memory.clear();
    ZonaiCookie.authToken.remove();
  }

  @override
  Future<void> remove(String key) async {
    if (key == tokenKey) {
      ZonaiCookie.authToken.remove();
      return;
    }
    _memory.remove(key);
  }

  @override
  Future<void> save(String key, Object? value) async {
    if (key == tokenKey && value is String) {
      ZonaiCookie.authToken.write(value);
      return;
    }
    _memory[key] = value;
  }

  @override
  Future<void> saveAll(Map<String, Object?> values) async {
    for (final entry in values.entries) {
      await save(entry.key, entry.value);
    }
  }
}
