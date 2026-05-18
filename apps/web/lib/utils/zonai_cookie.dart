import 'package:zonai_web/utils/cookie_storage.dart';

/// Cookies used by the Zonai web app (non-secret UX flags, etc.).
///
/// [signedIn] is not HttpOnly so JavaScript can set/clear it on sign-in/out.
enum ZonaiCookie {
  signedIn(key: 'zonai_web_signed_in', maxAge: Duration(days: 180));

  const ZonaiCookie({required this.key, required this.maxAge});

  final String key;
  final Duration maxAge;

  /// `true` when the stored value equals `'1'`.
  bool readFlag() => CookieStorage.read(this) == '1';

  /// Persists `'1'` or removes the cookie when [value] is false.
  void writeFlag(bool value) {
    if (value) {
      CookieStorage.write(this, '1');
    } else {
      CookieStorage.remove(this);
    }
  }

  String? read() => CookieStorage.read(this);

  void write(String value) => CookieStorage.write(this, value);

  void remove() => CookieStorage.remove(this);

  @override
  String toString() => key;
}
