import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

/// Explicit light/dark choice. `null` follows the OS color scheme.
enum ThemePreference {
  light,
  dark,
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemePreference?>(ThemeNotifier.new);

class ThemeNotifier extends Notifier<ThemePreference?> {
  static const storageKey = 'zonai_theme';

  @override
  ThemePreference? build() {
    if (!ref.binding.isClient) return null;
    final stored = _readStored();
    _applyDocumentAttribute(stored);
    return stored;
  }

  /// Switches between light and dark based on the effective appearance.
  void toggle() {
    setTheme(isDarkEffective ? ThemePreference.light : ThemePreference.dark);
  }

  void setTheme(ThemePreference preference) {
    state = preference;
    _writeStored(preference);
    _applyDocumentAttribute(preference);
  }

  /// Clears the stored preference so the OS color scheme is used.
  void useSystem() {
    state = null;
    _clearStored();
    _applyDocumentAttribute(null);
  }

  bool get isDarkEffective {
    final pref = state;
    if (pref == ThemePreference.dark) return true;
    if (pref == ThemePreference.light) return false;
    return _systemPrefersDark();
  }

  static ThemePreference? _readStored() {
    try {
      return switch (web.window.localStorage.getItem(storageKey)) {
        'light' => ThemePreference.light,
        'dark' => ThemePreference.dark,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static void _writeStored(ThemePreference preference) {
    try {
      web.window.localStorage.setItem(storageKey, preference.name);
    } catch (_) {}
  }

  static void _clearStored() {
    try {
      web.window.localStorage.removeItem(storageKey);
    } catch (_) {}
  }

  static void _applyDocumentAttribute(ThemePreference? preference) {
    try {
      final root = web.document.documentElement;
      if (root == null) return;
      if (preference == null) {
        root.removeAttribute('data-theme');
      } else {
        root.setAttribute('data-theme', preference.name);
      }
    } catch (_) {}
  }

  static bool _systemPrefersDark() {
    try {
      return web.window.matchMedia('(prefers-color-scheme: dark)').matches;
    } catch (_) {
      return false;
    }
  }
}
