import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

final homeUiProvider = NotifierProvider<HomeUiNotifier, HomeUiState>(HomeUiNotifier.new);

final class HomeUiState {
  const HomeUiState({
    this.sidebarCollapsed = false,
    this.sidebarToggling = false,
    this.settingsOpen = false,
    this.systemTablesExpanded = false,
    this.mobileNavOpen = false,
    this.mobileNavClosing = false,
  });

  final bool sidebarCollapsed;
  /// True during the 0.2s collapse/expand animation so the width transition stays active.
  final bool sidebarToggling;
  final bool settingsOpen;
  final bool systemTablesExpanded;
  final bool mobileNavOpen;
  /// True during the 0.2s close animation so the sidebar CSS transition stays active.
  final bool mobileNavClosing;

  /// Rail/minimal sidebar layout; suppressed while the mobile drawer is open.
  bool get sidebarVisuallyCollapsed => sidebarCollapsed && !mobileNavOpen;
}

class HomeUiNotifier extends Notifier<HomeUiState> {
  static const _collapsedKey = 'zonai_sidebar_collapsed';
  static const _systemOpenKey = 'zonai_sidebar_system_open';

  Timer? _mobileNavCloseTimer;
  Timer? _sidebarToggleTimer;

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
    _mobileNavCloseTimer?.cancel();
    _mobileNavCloseTimer = null;
    _sidebarToggleTimer?.cancel();
    state = HomeUiState(
      sidebarCollapsed: collapsed,
      sidebarToggling: true,
      settingsOpen: collapsed ? false : state.settingsOpen,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: false,
      mobileNavClosing: false,
    );
    _sidebarToggleTimer = Timer(const Duration(milliseconds: 220), () {
      state = HomeUiState(
        sidebarCollapsed: state.sidebarCollapsed,
        sidebarToggling: false,
        settingsOpen: state.settingsOpen,
        systemTablesExpanded: state.systemTablesExpanded,
        mobileNavOpen: state.mobileNavOpen,
        mobileNavClosing: state.mobileNavClosing,
      );
    });
    _writeCollapsed(collapsed);
  }

  void toggleSystemTables() {
    setSystemTablesExpanded(!state.systemTablesExpanded);
  }

  void setSystemTablesExpanded(bool expanded) {
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      sidebarToggling: state.sidebarToggling,
      settingsOpen: state.settingsOpen,
      systemTablesExpanded: expanded,
      mobileNavOpen: state.mobileNavOpen,
      mobileNavClosing: state.mobileNavClosing,
    );
    _writeSystemOpen(expanded);
  }

  void openMobileNav() {
    _mobileNavCloseTimer?.cancel();
    _mobileNavCloseTimer = null;
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      sidebarToggling: state.sidebarToggling,
      settingsOpen: state.settingsOpen,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: true,
      mobileNavClosing: false,
    );
  }

  void closeMobileNav() {
    if (!state.mobileNavOpen) return;
    captureSidebarScrollFromDom();
    _mobileNavCloseTimer?.cancel();
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      sidebarToggling: state.sidebarToggling,
      settingsOpen: state.settingsOpen,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: false,
      mobileNavClosing: true,
    );
    _mobileNavCloseTimer = Timer(const Duration(milliseconds: 220), () {
      state = HomeUiState(
        sidebarCollapsed: state.sidebarCollapsed,
        sidebarToggling: state.sidebarToggling,
        settingsOpen: state.settingsOpen,
        systemTablesExpanded: state.systemTablesExpanded,
        mobileNavOpen: false,
        mobileNavClosing: false,
      );
    });
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
      sidebarToggling: state.sidebarToggling,
      settingsOpen: true,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: state.mobileNavOpen,
      mobileNavClosing: state.mobileNavClosing,
    );
  }

  void closeSettings() {
    state = HomeUiState(
      sidebarCollapsed: state.sidebarCollapsed,
      sidebarToggling: state.sidebarToggling,
      settingsOpen: false,
      systemTablesExpanded: state.systemTablesExpanded,
      mobileNavOpen: state.mobileNavOpen,
      mobileNavClosing: state.mobileNavClosing,
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
