// dart format width=100
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';
import 'package:zonai_schema/src/handlers/messages/stdin.dart';
import 'package:zonai_schema/src/handlers/messages/stdout.dart';

/// Bidirectional map channel between host and worker MessageHandler.
///
/// Stdio workers use [StdioMessageIo] (framed MessagePack). Isolate workers
/// use [SendPortMessageIo] (plain maps over SendPort).
abstract class MessageIo {
  Stream<Map<String, dynamic>> get incoming;

  void send(Map<String, dynamic> message);

  void dispose();
}

final class StdioMessageIo implements MessageIo {
  StdioMessageIo({Stdin? stdin, Stdout? stdout})
    : _stdin = stdin ?? Stdin(),
      _stdout = stdout ?? Stdout(),
      _controller = StreamController<Map<String, dynamic>>.broadcast() {
    _subscription = _stdin.stream.listen(_onChunk, onError: _controller.addError);
  }

  final Stdin _stdin;
  final Stdout _stdout;
  final StreamController<Map<String, dynamic>> _controller;
  final IpcFrameBuffer _frames = IpcFrameBuffer();
  StreamSubscription<List<int>>? _subscription;

  @override
  Stream<Map<String, dynamic>> get incoming => _controller.stream;

  void _onChunk(List<int> chunk) {
    try {
      for (final map in _frames.push(chunk)) {
        _controller.add(map);
      }
    } on FormatException catch (e, stack) {
      _controller.addError(e, stack);
    }
  }

  @override
  void send(Map<String, dynamic> message) {
    _stdout.writeFrame(IpcCodec.encode(message));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
    _frames.clear();
  }
}

/// Isolate-side (or host-side peer) channel backed by a [SendPort].
///
/// Protocol: peer first receives this side's [SendPort] via [hostPort], then
/// both sides exchange `Map<String, dynamic>` messages.
final class SendPortMessageIo implements MessageIo {
  SendPortMessageIo(SendPort peer)
    : _peer = peer,
      _local = ReceivePort(),
      _controller = StreamController<Map<String, dynamic>>.broadcast() {
    _peer.send(_local.sendPort);
    _subscription = _local.listen(_onMessage);
  }

  /// Host-side constructor: spawn already sent [local] to the isolate; use the
  /// isolate's reply port as [peer].
  SendPortMessageIo.host({required SendPort peer, required ReceivePort local})
    : _peer = peer,
      _local = local,
      _controller = StreamController<Map<String, dynamic>>.broadcast() {
    _subscription = _local.listen(_onMessage);
  }

  final SendPort _peer;
  final ReceivePort _local;
  final StreamController<Map<String, dynamic>> _controller;
  StreamSubscription<dynamic>? _subscription;

  @override
  Stream<Map<String, dynamic>> get incoming => _controller.stream;

  void _onMessage(dynamic raw) {
    if (raw is! Map) {
      _controller.addError(FormatException('Isolate IPC expected Map, got ${raw.runtimeType}'));
      return;
    }
    _controller.add(coerceStringKeyedMap(raw));
  }

  @override
  void send(Map<String, dynamic> message) {
    _peer.send(message);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _local.close();
    _controller.close();
  }
}

/// Deep-converts isolate maps so nested values match `fromJson` expectations
/// (`Map<String, dynamic>`, not `Map<dynamic, dynamic>`).
Map<String, dynamic> coerceStringKeyedMap(Map raw) {
  return {for (final entry in raw.entries) entry.key.toString(): _coerce(entry.value)};
}

Object? _coerce(Object? value) {
  if (value is Map) return coerceStringKeyedMap(value);
  if (value is List) return [for (final item in value) _coerce(item)];
  if (value is TypedData) return value;
  return value;
}
