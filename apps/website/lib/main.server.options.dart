// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:zonai_website/src/interactive/code_tabs.dart' as _code_tabs;
import 'package:zonai_website/src/interactive/install_command.dart'
    as _install_command;
import 'package:zonai_website/src/interactive/stream_demo.dart' as _stream_demo;
import 'package:zonai_website/src/sections/dashboard.dart' as _dashboard;
import 'package:zonai_website/src/sections/download.dart' as _download;
import 'package:zonai_website/src/sections/features.dart' as _features;
import 'package:zonai_website/src/sections/footer.dart' as _footer;
import 'package:zonai_website/src/sections/hero.dart' as _hero;
import 'package:zonai_website/src/sections/honest.dart' as _honest;
import 'package:zonai_website/src/sections/live.dart' as _live;
import 'package:zonai_website/src/sections/nav.dart' as _nav;
import 'package:zonai_website/src/sections/pipeline.dart' as _pipeline;
import 'package:zonai_website/src/sections/start.dart' as _start;
import 'package:zonai_website/src/sections/tour.dart' as _tour;
import 'package:zonai_website/src/app.dart' as _app;
import 'package:zonai_website/src/code.dart' as _code;
import 'package:zonai_website/src/theme.dart' as _theme;
import 'package:zonai_website/src/ui.dart' as _ui;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _code_tabs.CodeTabs: ClientTarget<_code_tabs.CodeTabs>(
      'code_tabs',
      params: __code_tabsCodeTabs,
    ),
    _install_command.InstallCommand:
        ClientTarget<_install_command.InstallCommand>(
          'install_command',
          params: __install_commandInstallCommand,
        ),
    _stream_demo.StreamDemo: ClientTarget<_stream_demo.StreamDemo>(
      'stream_demo',
    ),
    _nav.SiteNav: ClientTarget<_nav.SiteNav>('nav'),
  },
  styles: () => [
    ..._theme.globalStyles,
    ..._ui.docsLinkStyles,
    ..._ui.textStyles,
    ..._app.ZonaiSite.styles,
    ..._code.CodeBlock.styles,
    ..._code.CodeWindow.styles,
    ..._ui.LinkButton.styles,
    ..._ui.RuneMark.styles,
    ..._ui.Section.styles,
    ..._code_tabs.CodeTabsState.styles,
    ..._install_command.InstallCommandState.styles,
    ..._stream_demo.StreamDemoState.styles,
    ..._dashboard.AdminDashboard.styles,
    ..._download.Downloads.styles,
    ..._features.Features.styles,
    ..._footer.SiteFooter.styles,
    ..._hero.Hero.styles,
    ..._honest.Honest.styles,
    ..._live.LiveQueries.styles,
    ..._nav.SiteNavState.styles,
    ..._pipeline.Pipeline.styles,
    ..._start.FinalCta.styles,
    ..._start.QuickStart.styles,
    ..._tour.Tour.styles,
  ],
);

Map<String, Object?> __code_tabsCodeTabs(_code_tabs.CodeTabs c) => {
  'labels': c.labels,
  'filenames': c.filenames,
  'sources': c.sources,
  'captions': c.captions,
  'langs': c.langs,
};
Map<String, Object?> __install_commandInstallCommand(
  _install_command.InstallCommand c,
) => {'command': c.command};
