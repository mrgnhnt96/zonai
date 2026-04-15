import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:zonai_schema/src/handlers/messages/stdin.dart';
import 'package:zonai_schema/src/handlers/messages/stdout.dart';

part 'response.dart';
part 'request.dart';

class MessageHandler {
  MessageHandler({required this.onMessage, Stdin? stdin, Stdout? stdout})
    : stdin = Stdin(),
      stdout = Stdout();

  final Future<Request?> Function(Response) onMessage;
  final Stdin stdin;
  final Stdout stdout;

  bool _listening = false;
  Future<void> listen() async {
    if (_listening) return;
    _listening = true;

    final stream = stdin.stream.transform(utf8.decoder);
    await for (final msg in stream) {
      final message = msg.trim();
      print('message: "$message"');
      print("$message == 'kill' (${message == 'kill'})");
      if (message case 'kill' || 'quit' || 'exit' || 'q') {
        break;
      }

      if (_decode(message) case final msg?) {
        switch (msg) {
          case ResponsePing():
            send(SendMessageDebug(message: 'connection healthy'));
            continue;
          case ResponseKill():
            break;
        }

        onMessage(msg).then(send);
      }
    }

    _listening = false;
    print('done listening');
  }

  void send(Request? message) {
    if (message == null) return;
    assert(_listening, 'Cannot send a message while not listening');

    String json;
    try {
      json = jsonEncode(message);
    } catch (e) {
      assert(false, 'Failed to encode message: $e');
      return;
    }

    stdout.write(json);
  }

  Response? _decode(String message) {
    try {
      return switch (jsonDecode(message)) {
        final Map<String, dynamic> json => Response.fromJson(json),
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
