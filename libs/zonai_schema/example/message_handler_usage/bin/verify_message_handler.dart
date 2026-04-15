import 'dart:io';

import 'package:zonai_schema/src/handlers/messages/message_handler.dart';

/// Exercises [MessageHandler]: reads [Request] JSON from stdin, writes
/// [Response] JSON to stdout. Instructions go to stderr so the protocol stream
/// stays clean.
///
/// [Stdin] registers with Zonai CLI [cleanUp]; a scope is required.
Future<void> main() async {
  print('MessageHandler demo — JSON lines on stdin, JSON replies on stdout.');
  print(r'Try: {"path":"ping"}');
  print('Type kill, quit, exit, or q on a line to stop (see handler).');

  final handler = MessageHandler(
    onMessage: (response) async {
      // Only non-ping / non-kill responses reach here (see handler switch).
      return DebugResponse(message: 'onMessage saw path: ${response.path}');
    },
  );

  await handler.listen();

  handler.dispose();

  print('done');
}
