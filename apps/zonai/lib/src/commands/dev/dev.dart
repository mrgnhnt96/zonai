import 'dart:io';

import 'package:nocterm/nocterm.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_logger/zonai_logger.dart' as zonai_log;
import 'package:zonai_schema/payloads.dart';

import '../../deps/keyboard_input.dart';
import '../../deps/kill.dart';
import '../../deps/logger.dart';
import '../../deps/stdin.dart' as zonai_stdin;
import '../../deps/zonai_db.dart';
import '../../utils/admin_create_shape.dart';
import 'actions/project_init.dart';
import 'components/dev_app.dart';
import 'dev_form_options.dart';

Future<int> dev() async {
  if (await ensureProjectInitialized() case final exitCode?) {
    return exitCode;
  }

  // Zonai's stdin wrapper and kill handler conflict with nocterm's TUI:
  // - io.stdin only allows one listener (nocterm needs it for keyboard/mouse input)
  // - Kill's SIGINT handler exits without disabling mouse tracking or alt-screen
  await zonai_stdin.stdin.releaseForAlternateApp();
  keyboardInput.releaseForAlternateApp();
  kill.suspendSignals();

  // zonaiDB and logger must run before the TUI: nocterm owns stdout once runApp starts.
  List<ColumnShape> adminExtraFields = const [];
  String? adminShapeError;
  var formOptions = const DevFormOptions(
    emailTemplates: [],
    cronJobNames: [],
    schemaTables: [],
  );

  try {
    formOptions = await loadDevFormOptions();
  } catch (_) {}

  try {
    final tableShape = await resolveAdminTableShape(zonaiDB);
    adminExtraFields = adminExtraCreateFields(tableShape.columns);
  } catch (e) {
    adminShapeError = '$e';
  }

  // Logger writeln is async; nocterm writes to stdout synchronously during init.
  // Drain pending stdout so nocterm does not hit "StreamSink is bound to a stream".
  await stdout.flush();

  // nocterm owns the alternate screen buffer — logger must not write to the real
  // terminal or lines bleed through the layout (especially with --log verbose).
  final discardSink = zonai_log.CallbackSink(callback: (_) {});
  final tuiLogger = zonai_log.Logger(
    level: logger.level,
    stdout: discardSink,
    stderr: discardSink,
  );

  await runScoped(() async {
    await runApp(
      DevApp(
        adminExtraFields: adminExtraFields,
        adminShapeError: adminShapeError,
        formOptions: formOptions,
      ),
    );
  }, values: {loggerProvider.overrideWith(() => tuiLogger)});
  return 0;
}

