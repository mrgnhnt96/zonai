import 'package:universal_web/web.dart' as web;
import 'package:zonai_web/utils/zonai_cookie.dart';

/// Reads and writes `document.cookie` using [ZonaiCookie] metadata from any cookie enum.
abstract final class CookieStorage {
  CookieStorage._();

  /// Returns the stored value for [cookie], or `null` if missing/unreadable.
  static String? read(ZonaiCookie cookie) {
    try {
      final raw = web.document.cookie;
      if (raw.isEmpty) return null;
      for (final segment in raw.split(';')) {
        final trimmed = segment.trim();
        final eq = trimmed.indexOf('=');
        if (eq <= 0) continue;
        final name = trimmed.substring(0, eq).trim();
        final value = trimmed.substring(eq + 1).trim();
        if (name != cookie.key) continue;
        try {
          return Uri.decodeComponent(value);
        } catch (_) {
          return value;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Persists [value] with this cookie's [ZonaiCookie.maxAge].
  static void write(ZonaiCookie cookie, String value) {
    try {
      final encoded = Uri.encodeComponent(value);
      web.document.cookie = '${cookie.key}=$encoded; Path=/; Max-Age=${cookie.maxAge.inSeconds}; SameSite=Lax';
    } catch (_) {}
  }

  /// Removes the cookie from the browser (best-effort).
  static void remove(ZonaiCookie cookie) {
    try {
      web.document.cookie = '${cookie.key}=; Path=/; Max-Age=0; SameSite=Lax';
    } catch (_) {}
  }
}
