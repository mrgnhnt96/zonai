import 'dart:async';
import 'dart:convert';

import 'package:nocterm/nocterm.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/payloads.dart';

import '../../../deps/config_resolver.dart';
import '../../../messengers/cron_mailman.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import '../../../utils/admin_create_shape.dart';
import '../../../utils/email_template_render.dart';
import '../../../utils/terminal_pointer.dart';
import '../actions/clipboard.dart';
import '../actions/create_part.dart';
import '../actions/create_schema.dart';
import '../actions/schema_scaffold.dart';
import '../actions/open_html_preview.dart';
import '../actions/dev_action_tracker.dart';
import '../actions/part_scaffold.dart';
import '../actions/server_controller.dart';
import '../actions/subprocess_runner.dart';
import '../actions/worker_watch_controller.dart';
import '../dev_form_options.dart';
import '../../../deps/logger.dart';
import '../../../utils/schema_tables.dart';
import 'dev_header.dart';
import 'dev_input_mode.dart';
import 'dev_input_panel.dart';
import 'dev_menu_item.dart';
import 'dev_menu_panel.dart';
import 'dev_output_panel.dart';
import 'dev_theme.dart';

class DevApp extends StatefulComponent {
  const DevApp({
    required this.adminExtraFields,
    required this.formOptions,
    this.adminShapeError,
    super.key,
  });

  final List<ColumnShape> adminExtraFields;
  final DevFormOptions formOptions;
  final String? adminShapeError;

  @override
  State<DevApp> createState() => _DevAppState();
}

class _DevAppState extends State<DevApp> {
  static const _maxLines = 500;
  static const _selectionColor = Color(0xFF2D4A6F);
  static const _toastDuration = Duration(seconds: 3);

  late final ServerController _server;
  late final DevActionTracker _actionTracker;
  late final WorkerWatchController _workerWatch;
  late DevFormOptions _formOptions;
  final _outputLines = <DevOutputLine>[];
  int _menuIndex = 0;
  DevInputMode _inputMode = DevInputMode.none;
  bool _hasOutputSelection = false;
  int _selectionAreaKey = 0;
  bool _serverRunning = false;
  final _scrollController = AutoScrollController();
  Timer? _toastTimer;
  String? _toastMessage;
  var _toastIsError = false;
  late final void Function(LogDetails) _logCallback;

  @override
  void initState() {
    super.initState();
    _formOptions = component.formOptions;
    _actionTracker = DevActionTracker(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _server = ServerController(_addOutput, (running) {
      setState(() => _serverRunning = running);
    });
    _workerWatch = WorkerWatchController(
      tracker: _actionTracker,
      onOutput: _addOutput,
      onSchemasChanged: _reloadFormOptions,
    );
    _logCallback = _onLog;
    logger.addCallback(_logCallback);
    _workerWatch.start();
    if (kIsCompiled) {
      _server.start();
    } else {
      _server.probe();
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    logger.removeCallback(_logCallback);
    _workerWatch.dispose();
    _actionTracker.dispose();
    _server.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reloadFormOptions() async {
    try {
      final options = await loadDevFormOptions();
      if (!mounted) return;
      setState(() => _formOptions = options);
    } catch (_) {}
  }

  void _onLog(LogDetails details) {
    if (details.level < logger.level) return;
    final prefix = switch (details.level) {
      Level.warning => '[warn]',
      Level.error => '[err]',
      _ => null,
    };
    final message = prefix == null
        ? details.message
        : '$prefix ${details.message}';
    scheduleMicrotask(() {
      if (!mounted) return;
      _addOutput(message, level: details.level);
    });
  }

  void _showToast(String message, {required bool isError}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
    });
    _toastTimer = Timer(_toastDuration, () {
      if (!mounted) return;
      setState(() => _toastMessage = null);
    });
  }

  void _onSelectionCompleted(String text) {
    if (text.isEmpty) return;

    scheduleMicrotask(() async {
      final copied = await copyToSystemClipboard(text);
      if (!mounted) return;
      _showToast(
        copied ? 'Copied to clipboard' : 'Failed to copy',
        isError: !copied,
      );
    });
  }

  void _copyAllOutput() {
    if (_outputLines.isEmpty) {
      _showToast('Nothing to copy', isError: true);
      return;
    }

    final text = _outputLines.map((line) => line.text).join('\n');
    scheduleMicrotask(() async {
      final copied = await copyToSystemClipboard(text);
      if (!mounted) return;
      _showToast(
        copied ? 'Copied all logs to clipboard' : 'Failed to copy',
        isError: !copied,
      );
    });
  }

  void _addOutput(String line, {Level? level}) {
    setState(() {
      _outputLines.add((text: line, level: level));
      if (_outputLines.length > _maxLines) {
        _outputLines.removeRange(0, _outputLines.length - _maxLines);
      }
    });
  }

  void _clearOutput() {
    if (_outputLines.isEmpty) return;
    setState(() => _outputLines.clear());
    _scrollController.enableAutoScroll();
  }

  void _setInputMode(DevInputMode mode) {
    setState(() => _inputMode = mode);
  }

  void _clearInputMode() {
    setState(() => _inputMode = DevInputMode.none);
  }

  void _highlightMenuItem(int index) {
    setState(() {
      _menuIndex = index;
      _inputMode = DevInputMode.none;
    });
  }

  void _onOutputSelectionChanged(String text) {
    final hasSelection = text.isNotEmpty;
    if (_hasOutputSelection == hasSelection) return;
    setState(() => _hasOutputSelection = hasSelection);
  }

  void _clearOutputSelection() {
    if (!_hasOutputSelection) return;
    setState(() {
      _hasOutputSelection = false;
      _selectionAreaKey++;
    });
  }

  Future<void> _runCommand(List<String> args, {required String label}) async {
    try {
      final exitCode = await _actionTracker.run(
        label,
        () => runZonaiCommand(args, _addOutput),
        isSuccess: (code) => code == 0,
      );
      if (!mounted) return;
      if (exitCode != 0) {
        _showToast('$label failed', isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      _showToast('$label failed', isError: true);
    }
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: _inputMode == DevInputMode.none,
      onKeyEvent: _handleKey,
      child: _buildShell(),
    );
  }

  Component _buildShell() {
    return Container(
      decoration: BoxDecoration(color: DevTheme.bg),
      child: Stack(
        children: [
          Column(
            children: [
              DevHeader(
                runningActions: _actionTracker.actions,
                serverRunning: _serverRunning,
              ),
              Expanded(
                child: Row(
                  children: [
                    DevMenuPanel(
                      selectedIndex: _menuIndex,
                      serverRunning: _serverRunning,
                      onItemTap: _onMenuItemTap,
                    ),
                    Expanded(child: _buildContentColumn()),
                  ],
                ),
              ),
              DevHintBar(
                hints: devHintsFor(
                  _inputMode,
                  menuKey: devMenuItems[_menuIndex].key,
                ),
              ),
            ],
          ),
          _buildToastOverlay(),
        ],
      ),
    );
  }

  Component _buildToastOverlay() {
    final message = _toastMessage;
    if (message == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [DevToast(message: message, isError: _toastIsError)],
      ),
    );
  }

  Component _buildContentColumn() {
    if (_inputMode != DevInputMode.none) {
      return Column(
        children: [
          DevContentHeader(
            title: 'FORM',
            badge: _formBadgeFor(_inputMode),
            subtitle: devMenuItems[_menuIndex].description,
            destructive: _inputMode == DevInputMode.clearDatabase,
          ),
          Expanded(
            child: DevInputPanel(
              inputMode: _inputMode,
              adminExtraFields: component.adminExtraFields,
              adminShapeError: component.adminShapeError,
              formOptions: _formOptions,
              onMigrateCancel: _clearInputMode,
              onMigrateGenerateSubmit: _submitMigrateGenerate,
              onAdminCancel: _clearInputMode,
              onAdminSubmit: _submitAdmin,
              onEmailTestCancel: _clearInputMode,
              onEmailTestSubmit: _submitEmailTest,
              onEmailPreviewCancel: _clearInputMode,
              onEmailPreviewSubmit: _submitEmailPreview,
              onEmailTemplateCancel: _clearInputMode,
              onEmailTemplateSubmit: _submitEmailTemplate,
              onCronCancel: _clearInputMode,
              onCronSubmit: _submitCron,
              onClearCancel: _clearInputMode,
              onClearConfirm: _submitClearDatabase,
              onCreatePartCancel: _clearInputMode,
              onCreatePartSubmit: _submitCreatePart,
              onCreateSchemaCancel: _clearInputMode,
              onCreateSchemaSubmit: _submitCreateSchema,
              onRulesCancel: _clearInputMode,
              onRulesSubmit: _submitRules,
            ),
          ),
        ],
      );
    }

    final item = devMenuItems[_menuIndex];
    return Column(
      children: [
        DevContentHeader(
          title: item.hasContent ? 'OUTPUT' : 'LOGS',
          subtitle: item.hasContent ? item.description : null,
          trailing: DevFormButton(
            label: 'Copy all',
            focused: false,
            enabled: _outputLines.isNotEmpty,
            onTap: _copyAllOutput,
          ),
        ),
        Expanded(
          child: SelectionArea(
            key: ValueKey(_selectionAreaKey),
            selectionColor: _selectionColor,
            onSelectionChanged: _onOutputSelectionChanged,
            onSelectionCompleted: _onSelectionCompleted,
            child: DevOutputPanel(
              outputLines: _outputLines,
              scrollController: _scrollController,
              showEmptyState: item.hasContent,
            ),
          ),
        ),
      ],
    );
  }

  void _onMenuItemTap(int index) {
    _highlightMenuItem(index);
    if (_actionTracker.isBusy) return;
    _runMenuAction(devMenuItems[index].key);
  }

  bool _handleQuitKey() {
    if (_hasOutputSelection) {
      _clearOutputSelection();
      return true;
    }
    TerminalPointer.reset();
    TerminalBinding.instance.shutdown();
    return true;
  }

  bool _handleKey(KeyboardEvent event) {
    if (event.isControlPressed &&
        event.logicalKey == LogicalKey.keyC) {
      return _handleQuitKey();
    }

    if (event.isControlPressed &&
        event.logicalKey == LogicalKey.keyL &&
        _inputMode == DevInputMode.none) {
      _clearOutput();
      return true;
    }

    if (_actionTracker.isBusy && _inputMode == DevInputMode.none) return false;

    if (event.logicalKey == LogicalKey.escape &&
        _inputMode == DevInputMode.none &&
        devMenuItems[_menuIndex].key == 'l') {
      if (_hasOutputSelection) {
        _clearOutputSelection();
        return true;
      }
      _setInputMode(DevInputMode.rulesJwt);
      return true;
    }

    switch (event.logicalKey) {
      case LogicalKey.keyQ:
        return _handleQuitKey();
      case LogicalKey.arrowUp:
        _highlightMenuItem((_menuIndex - 1).clamp(0, devMenuItems.length - 1));
        return true;
      case LogicalKey.arrowDown:
        _highlightMenuItem((_menuIndex + 1).clamp(0, devMenuItems.length - 1));
        return true;
      case LogicalKey.enter:
      case LogicalKey.space:
        if (!_actionTracker.isBusy && _inputMode == DevInputMode.none) {
          _runMenuAction(devMenuItems[_menuIndex].key);
        }
        return true;
      case LogicalKey.keyS:
        _toggleServer();
        return true;
      case LogicalKey.keyU:
        if (!_actionTracker.isBusy) _applyMigrations();
        return true;
      case LogicalKey.keyM:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.migrateGenerate);
        return true;
      case LogicalKey.keyD:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.clearDatabase);
        return true;
      case LogicalKey.keyA:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.adminEmail);
        return true;
      case LogicalKey.keyE:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.emailTest);
        return true;
      case LogicalKey.keyV:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.emailPreview);
        return true;
      case LogicalKey.keyT:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.emailTemplate);
        return true;
      case LogicalKey.keyC:
        if (!event.isControlPressed && !_actionTracker.isBusy) {
          _compileWorkers();
        }
        return true;
      case LogicalKey.keyP:
        _pingExecutables();
        return true;
      case LogicalKey.keyJ:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.cronRun);
        return true;
      case LogicalKey.keyL:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.rulesJwt);
        return true;
      case LogicalKey.keyF:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.createPart);
        return true;
      case LogicalKey.keyN:
        if (!_actionTracker.isBusy) _setInputMode(DevInputMode.createSchema);
        return true;
    }
    return false;
  }

  void _runMenuAction(String key) {
    switch (key) {
      case 's':
        _toggleServer();
      case 'u':
        _applyMigrations();
      case 'm':
        _setInputMode(DevInputMode.migrateGenerate);
      case 'd':
        _setInputMode(DevInputMode.clearDatabase);
      case 'a':
        _setInputMode(DevInputMode.adminEmail);
      case 'e':
        _setInputMode(DevInputMode.emailTest);
      case 'v':
        _setInputMode(DevInputMode.emailPreview);
      case 't':
        _setInputMode(DevInputMode.emailTemplate);
      case 'c':
        _compileWorkers();
      case 'p':
        _pingExecutables();
      case 'j':
        _setInputMode(DevInputMode.cronRun);
      case 'l':
        _setInputMode(DevInputMode.rulesJwt);
      case 'f':
        _setInputMode(DevInputMode.createPart);
      case 'n':
        _setInputMode(DevInputMode.createSchema);
    }
  }

  void _submitMigrateGenerate(String name) {
    _clearInputMode();
    _addOutput('--- Generate migration: $name ---');
    () async {
      await _runCommand([
        'db',
        'migrate',
        'generate',
        '--name',
        name,
      ], label: 'Generate migration');
    }();
  }

  void _applyMigrations() {
    _addOutput('--- Applying migrations ---');
    () async {
      await _runCommand(['db', 'migrate', 'apply'], label: 'Apply migrations');
    }();
  }

  void _submitAdmin(
    String email,
    String password,
    Map<String, String> extraFields,
  ) {
    _clearInputMode();
    _addOutput('--- Create admin ---');
    () async {
      final object = buildAdminCreateObject(
        extraFields: component.adminExtraFields,
        values: extraFields,
      );

      final args = [
        'db',
        'admin',
        'add',
        '--email',
        email,
        '--password',
        password,
      ];
      if (object.isNotEmpty) {
        args.addAll(['--data', jsonEncode(object)]);
      }

      await _runCommand(args, label: 'Create admin');
    }();
  }

  Future<String> _resolveAppName() async {
    try {
      final config = await configResolver.resolve();
      return config.applicationName;
    } catch (_) {
      return 'My App';
    }
  }

  void _submitEmailPreview(String template, Map<String, String> variables) {
    () async {
      try {
        final appName = await _resolveAppName();
        final html = renderEmailTemplate(
          templateName: template,
          variables: variables,
          appName: appName,
        );
        await _openEmailInBrowser(
          html: html,
          filename: template,
          outputLabel: 'Preview email: $template',
        );
      } catch (e) {
        if (!mounted) return;
        _showToast('$e', isError: true);
      }
    }();
  }

  Future<void> _openEmailInBrowser({
    required String html,
    required String filename,
    required String outputLabel,
  }) async {
    final path = await openHtmlPreview(html, filename: filename);
    if (!mounted) return;

    if (path == null) {
      _showToast('Failed to open browser', isError: true);
      return;
    }

    _addOutput('--- $outputLabel ---');
    _addOutput('Opened: $path');
    _showToast('Opened in browser', isError: false);
  }

  void _submitEmailTest(String to, String template) {
    _clearInputMode();
    _addOutput('--- Send test email ---');
    () async {
      await _runCommand([
        'db',
        'email',
        'test',
        '--to',
        to,
        '--template',
        template,
      ], label: 'Send test email');
    }();
  }

  void _submitEmailTemplate(String name) {
    _clearInputMode();
    _addOutput('--- Create email template ---');
    () async {
      await _runCommand([
        'db',
        'email',
        'template',
        'create',
        name,
      ], label: 'Create email template');
    }();
  }

  void _submitCron(String name) {
    _clearInputMode();
    _addOutput('--- Run cron job ---');
    () async {
      try {
        await _actionTracker.run('Run cron job', () async {
          final mailman = CronMailman();
          try {
            final response = await mailman.send<CronJobRunResponse>(
              RunCronJobRequest(name: name),
            );
            if (!response.accepted) {
              throw StateError(response.error ?? 'Cron job was not accepted');
            }
            _addOutput('Cron job started: $name');
          } finally {
            await mailman.kill(failPending: false);
          }
        });
        if (!mounted) return;
      } catch (error) {
        if (!mounted) return;
        _addOutput('Error: $error');
        _showToast('Run cron job failed', isError: true);
      }
    }();
  }

  void _submitClearDatabase() {
    _clearInputMode();
    _addOutput('--- Clear database ---');
    () async {
      await _runCommand(['db', 'clear', '--yes'], label: 'Clear database');
    }();
  }

  bool _submitCreateSchema(
    String entityName,
    SchemaTableKind tableKind,
    SchemaAuthConfig authConfig,
    bool runMigration,
  ) {
    _addOutput('--- Create schema ---');

    final result = createSchema(
      rawEntityName: entityName,
      kind: tableKind,
      authConfig: authConfig,
    );

    if (!result.ok) {
      _addOutput('Error: ${result.error}');
      _showToast(result.error!, isError: true);
      return false;
    }

    _clearInputMode();
    _addOutput('Created ${result.schemaPath}');
    _addOutput('Updated ${result.idsPath}');
    _showToast('Created ${result.schemaPath}', isError: false);
    unawaited(_reloadFormOptions());

    if (runMigration) {
      final migrationName = 'add_${result.names!.tableName}';
      _addOutput('--- Generate migration: $migrationName ---');
      () async {
        await _runCommand([
          'db',
          'migrate',
          'generate',
          '--name',
          migrationName,
        ], label: 'Generate migration');
        if (!mounted) return;
        _addOutput('--- Applying migrations ---');
        await _runCommand([
          'db',
          'migrate',
          'apply',
        ], label: 'Apply migrations');
      }();
    }

    return true;
  }

  bool _submitCreatePart(
    WorkerPartType partType,
    String className,
    SchemaTableInfo? table,
  ) {
    _addOutput('--- Create ${partType.label.toLowerCase()} ---');

    final result = createWorkerPart(
      type: partType,
      rawClassName: className,
      table: table,
    );

    if (result.ok) {
      _clearInputMode();
      _addOutput('Created ${result.path}');
      _showToast('Created ${result.path}', isError: false);
      return true;
    }

    _addOutput('Error: ${result.error}');
    _showToast(result.error!, isError: true);
    return false;
  }

  void _toggleServer() {
    if (_server.isRunning) {
      _server.stop();
    } else {
      _server.start();
    }
  }

  void _compileWorkers() {
    if (_actionTracker.isBusy) return;
    () async {
      await _workerWatch.compileAll();
    }();
  }

  void _pingExecutables() {
    if (_actionTracker.isBusy) return;
    _addOutput('--- Pinging executables ---');
    () async {
      await _runCommand(['ping'], label: 'Ping');
    }();
  }

  void _submitRules(String? jwt) {
    _clearInputMode();
    _addOutput('--- Listing rules ---');
    () async {
      final args = <String>['rules', 'list'];
      if (jwt != null) {
        args.addAll(['--jwt', jwt]);
      }
      await _runCommand(args, label: 'Table rules');
    }();
  }

  String? _formBadgeFor(DevInputMode mode) {
    return switch (mode) {
      DevInputMode.migrateGenerate => 'migration',
      DevInputMode.adminEmail || DevInputMode.adminPassword => 'admin',
      DevInputMode.emailTest => 'email',
      DevInputMode.emailPreview => 'preview',
      DevInputMode.emailTemplate => 'template',
      DevInputMode.cronRun => 'cron',
      DevInputMode.createPart => 'scaffold',
      DevInputMode.createSchema => 'schema',
      DevInputMode.rulesJwt => 'rules',
      DevInputMode.clearDatabase => 'destructive',
      DevInputMode.none || DevInputMode.migrateApply => null,
    };
  }
}
