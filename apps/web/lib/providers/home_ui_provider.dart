import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

final homeUiProvider = NotifierProvider<HomeUiNotifier, HomeUiState>(HomeUiNotifier.new);

final class HomeUiState {
  const HomeUiState({
    this.sidebarCollapsed = false,
    this.settingsOpen = false,
    this.systemTablesExpanded = false,
    this.mobileNavOpen = false,
  });

  final bool sidebarCollapsed;
  final bool settingsOpen;
  final bool systemTablesExpanded;
  final bool mobileNavOpen;

  /// Rail/minimal sidebar layout; suppressed while the mobile drawer is open.
  bool get sidebarVisuallyCollapsed => sidebarCollapsed && !mobileNavOpen;
}

class HomeUiNotifier extends Notifier<HomeUiState> {
  static const _collapsedKey = 'zonai_sidebar_collapsed';
  static const _systemOpenKey = 'zonai_sidebar_system_open';

  double bodyScrollTop = 0;
  double railScrollTop = 0;

  void saveSidebarScrollTop({required bool body, required double scrollTop}) {
    if (body) {
      bodyScrollTop = scrollTop;
    } else {
      railScrollTop = scrollTop;
    }
  }

  double savedSidebarScrollTopFor({required bool body}) => body ? bodyScrollTop : railScrollTop;

  void captureSidebarScrollFromDom() {
    if (!ref.binding.isClient) return;
    try {
      final body = web.document.querySelector('.home-sidebar-body');
      if (body != null) {
        saveSidebarScrollTop(body: true, scrollTop: body.scrollTop.toDouble());
      }
      final rail = web.document.querySelector('.home-sidebar-rail');
      if (rail != null) {
        saveSidebarScrollTop(body: false, scrollTop: rail.scrollTop.toDouble());
      }
    } catch (_) {}
  }

  @override
  HomeUiState build() {
    if (!ref.binding.isClient) {
      return const HomeUiState();
    }
    return HomeUiState(
      sidebarCollapsed: _readCollapsed(),
      systemTablesExpanded: _readSystemOpen(),
    );
  }

  void toggleSidebar() {
    setSidebarCollapsed(!state.sidebarCollapsed);
  }

  void setSidebarCollapsed(bool collapsed) {
    captureSidebarScrollFromDom();
    state = HomeUiState(
      sidebarCollapsed: collapsed,
      settingsOpen: collapsed ? false : state.settingsOpen,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: false,
    );
    _writeCollapsed(collapsed);
  }

  void toggleSystemTables() {
    setSystemTablesExpanded(!state.systemTablesExpanded);
  }

  void setSystemTablesExpanded(bool expanded) {
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      settingsOpen: state.settingsOpen,
      systemTablesExpanded: expanded,
      mobileNavOpen: state.mobileNavOpen,
    );
    _writeSystemOpen(expanded);
  }

  void openMobileNav() {
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      settingsOpen: state.settingsOpen,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: true,
    );
  }

  void closeMobileNav() {
    if (!state.mobileNavOpen) return;
    captureSidebarScrollFromDom();
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      settingsOpen: state.settingsOpen,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: false,
    );
  }

  void toggleMobileNav() {
    if (state.mobileNavOpen) {
      closeMobileNav();
    } else {
      openMobileNav();
    }
  }

  void openSettings() {
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      settingsOpen: true,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: state.mobileNavOpen,
    );
  }

  void closeSettings() {
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      settingsOpen: false,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: state.mobileNavOpen,
    );
  }

  void toggleSettings() {
    if (state.settingsOpen) {
      closeSettings();
    } else {
      openSettings();
    }
  }

  static bool _readCollapsed() {
    try {
      return web.window.localStorage.getItem(_collapsedKey) == '1';
    } catch (_) {
      return false;
    }
  }

  static void _writeCollapsed(bool collapsed) {
    try {
      if (collapsed) {
        web.window.localStorage.setItem(_collapsedKey, '1');
      } else {
        web.window.localStorage.removeItem(_collapsedKey);
      }
    } catch (_) {}
  }

  static bool _readSystemOpen() {
    try {
      return web.window.localStorage.getItem(_systemOpenKey) == '1';
    } catch (_) {
      return false;
    }
  }

  static void _writeSystemOpen(bool open) {
    try {
      if (open) {
        web.window.localStorage.setItem(_systemOpenKey, '1');
      } else {
        web.window.localStorage.removeItem(_systemOpenKey);
      }
    } catch (_) {}
  }
}
