// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:zonai_web/components/table_edit/foreign_key_picker_dialog.dart'
    as _foreign_key_picker_dialog;
import 'package:zonai_web/components/table_edit/table_edit_datetime_field.dart'
    as _table_edit_datetime_field;
import 'package:zonai_web/components/table_edit/table_edit_enum_multi_select.dart'
    as _table_edit_enum_multi_select;
import 'package:zonai_web/components/table_edit/table_edit_styles.dart'
    as _table_edit_styles;
import 'package:zonai_web/components/theme/ui_styles.dart' as _ui_styles;
import 'package:zonai_web/components/theme/zonai_boolean_check.dart'
    as _zonai_boolean_check;
import 'package:zonai_web/components/theme/zonai_enum_chip.dart'
    as _zonai_enum_chip;
import 'package:zonai_web/components/theme/zonai_tag.dart' as _zonai_tag;
import 'package:zonai_web/components/app_tooltip_overlay.dart'
    as _app_tooltip_overlay;
import 'package:zonai_web/components/auth_app_shell.dart' as _auth_app_shell;
import 'package:zonai_web/components/dashboard_screen.dart'
    as _dashboard_screen;
import 'package:zonai_web/components/home_app_shell.dart' as _home_app_shell;
import 'package:zonai_web/components/home_screen.dart' as _home_screen;
import 'package:zonai_web/components/home_settings_overlay.dart'
    as _home_settings_overlay;
import 'package:zonai_web/components/home_sidebar.dart' as _home_sidebar;
import 'package:zonai_web/components/schema_table_foreign_key_cell.dart'
    as _schema_table_foreign_key_cell;
import 'package:zonai_web/components/schema_table_photo_cell.dart'
    as _schema_table_photo_cell;
import 'package:zonai_web/components/syntax_highlighted_code.dart'
    as _syntax_highlighted_code;
import 'package:zonai_web/components/table_filter_datetime_field.dart'
    as _table_filter_datetime_field;
import 'package:zonai_web/components/table_row_detail_panel.dart'
    as _table_row_detail_panel;
import 'package:zonai_web/components/table_search_panel.dart'
    as _table_search_panel;
import 'package:zonai_web/components/toast_overlay.dart' as _toast_overlay;
import 'package:zonai_web/constants/theme.dart' as _theme;
import 'package:zonai_web/app.dart' as _app;

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
    _auth_app_shell.AuthAppShell: ClientTarget<_auth_app_shell.AuthAppShell>(
      'auth_app_shell',
      params: __auth_app_shellAuthAppShell,
    ),
    _home_app_shell.HomeAppShell: ClientTarget<_home_app_shell.HomeAppShell>(
      'home_app_shell',
      params: __home_app_shellHomeAppShell,
    ),
  },
  styles: () => [
    ..._schema_table_foreign_key_cell.schemaTableForeignKeyCellStyles,
    ..._schema_table_photo_cell.schemaTablePhotoCellStyles,
    ..._syntax_highlighted_code.syntaxHighlightedCodeStyles,
    ..._table_filter_datetime_field.tableFilterDatetimeStyles,
    ..._table_row_detail_panel.tableRowDetailPanelStyles,
    ..._table_search_panel.tableSearchPanelStyles,
    ..._table_search_panel.tableSearchSidePanelStyles,
    ..._foreign_key_picker_dialog.foreignKeyPickerDialogStyles,
    ..._table_edit_datetime_field.tableEditDatetimeStyles,
    ..._table_edit_enum_multi_select.tableEditEnumMultiSelectStyles,
    ..._table_edit_styles.tableEditSharedStyles,
    ..._ui_styles.zonaiUiStyles,
    ..._zonai_boolean_check.zonaiBooleanCheckStyles,
    ..._zonai_enum_chip.zonaiEnumChipStyles,
    ..._zonai_tag.zonaiTagStyles,
    ..._theme.styles,
    ..._app.App.styles,
    ..._app_tooltip_overlay.AppTooltipOverlay.styles,
    ..._auth_app_shell.AuthAppShell.styles,
    ..._dashboard_screen.DashboardScreen.styles,
    ..._home_app_shell.HomeAppShell.styles,
    ..._home_screen.HomeScreen.styles,
    ..._home_settings_overlay.HomeSettingsOverlay.styles,
    ..._home_sidebar.HomeSidebar.styles,
    ..._toast_overlay.ToastOverlay.styles,
  ],
);

Map<String, Object?> __auth_app_shellAuthAppShell(
  _auth_app_shell.AuthAppShell c,
) => {
  'initialPath': c.initialPath,
  'initialAppName': c.initialAppName,
  'initialAuthTypeNames': c.initialAuthTypeNames,
};
Map<String, Object?> __home_app_shellHomeAppShell(
  _home_app_shell.HomeAppShell c,
) => {
  'initialSqliteNames': c.initialSqliteNames,
  'initialDisplayNames': c.initialDisplayNames,
  'tablesLoadError': c.tablesLoadError,
  'initialSchemaShapes': c.initialSchemaShapes,
  'initialCollectionActions': c.initialCollectionActions,
  'initialPath': c.initialPath,
  'initialAppName': c.initialAppName,
  'initialPhotosConfig': c.initialPhotosConfig,
};
