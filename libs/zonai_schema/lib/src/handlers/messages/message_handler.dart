import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_schema/src/handlers/messages/stdin.dart';
import 'package:zonai_schema/src/handlers/messages/stdout.dart';

part 'request.dart';
part 'response.dart';
part 'deps/__log.dart';

class MessageHandler {
  MessageHandler({required this.onMessage, Stdin? stdin, Stdout? stdout})
    : stdin = Stdin(),
      stdout = Stdout();

  final Future<Response?> Function(UnknownRequest) onMessage;
  final Stdin stdin;
  final Stdout stdout;

  bool _listening = false;
  Future<void> listen() async {
    Future<void> _listen() async {
      if (_listening) return;
      _listening = true;

      final stream = stdin.stream.transform(utf8.decoder);
      await for (final msg in stream) {
        final message = msg.trim();
        if (message case 'kill' || 'quit' || 'exit' || 'q') {
          break;
        }

        if (_decode(message) case final msg?) {
          switch (msg) {
            case RequestPing():
              send(PongResponse(id: msg.id));
              continue;
            case RequestKill():
              break;
            case UnknownRequest():
              onMessage(msg).then(
                send,
                onError: (Object error, StackTrace stackTrace) {
                  logger.error(
                    'Error handling request',
                    error: error.toString(),
                    stackTrace: stackTrace.toString(),
                    properties: {
                      'path': msg.path,
                      'id': msg.id,
                      'request': msg.payload,
                    },
                  );
                  send(
                    MessageErrorResponse(
                      id: msg.id,
                      message: 'Error handling request',
                      error: error.toString(),
                      stackTrace: stackTrace.toString(),
                    ),
                  );
                },
              );
          }
        }
      }

      _listening = false;
    }

    await runScoped(
      _listen,
      values: {
        _loggerProvider.overrideWith(
          () => _Logger((
            message, {
            required level,
            properties,
            stackTrace,
            error,
          }) {
            send(
              DebugResponse(
                message: message,
                level: level,
                properties: properties,
                stackTrace: stackTrace,
                error: error,
              ),
            );
          }),
        ),
      },
    );
  }

  void send(Response? message) {
    if (message == null) return;
    assert(_listening, 'Cannot send a message while not listening');

    String json;
    try {
      json = jsonEncode(message);
    } catch (e) {
      assert(false, 'Failed to encode message: $e');
      print('Failed to encode message: $e');
      return;
    }

    stdout.writeln(json);
  }

  Request? _decode(String message) {
    try {
      return switch (jsonDecode(message)) {
        final Map<String, dynamic> json => Request.fromJson(json),
        _ => null,
      };
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    stdin.dispose();
    stdout.dispose();
  }
}
