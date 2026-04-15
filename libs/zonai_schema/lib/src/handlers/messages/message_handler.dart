import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:zonai_schema/src/handlers/messages/stdin.dart';
import 'package:zonai_schema/src/handlers/messages/stdout.dart';

part 'request.dart';
part 'response.dart';

class MessageHandler {
  MessageHandler({required this.onMessage, Stdin? stdin, Stdout? stdout})
    : stdin = Stdin(),
      stdout = Stdout();

  final Future<Response?> Function(Request) onMessage;
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
          case RequestPing():
            send(DebugResponse(message: 'connection healthy'));
            continue;
          case RequestKill():
            break;
        }

        onMessage(msg).then(send);
      }
    }

    _listening = false;
    print('done listening');
  }

  void send(Response? message) {
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
