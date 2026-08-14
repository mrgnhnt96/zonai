// dart format width=100
import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

/// Binary framing for host ↔ worker Mailman IPC.
///
/// Wire format (big-endian):
/// ```
/// magic[2] = 0x5A 0x4E ('ZN')
/// version[1] = 1
/// length[4] = payload byte count
/// payload[length] = MessagePack(map)
/// ```
///
/// Replaces newline-delimited JSON so we avoid UTF-8 + [LineSplitter] and get
/// a denser codec for the same [Request]/[Response] map shapes.
abstract final class IpcCodec {
  static const int magic0 = 0x5A; // 'Z'
  static const int magic1 = 0x4E; // 'N'
  static const int version = 1;
  static const int headerSize = 7;
  static const int maxPayloadBytes = 16 * 1024 * 1024;

  /// Encodes a JSON-compatible map into one framed MessagePack message.
  ///
  /// Nested objects that expose `toJson()` (the same contract [jsonEncode]
  /// relies on) are converted before packing so worker payloads that embed
  /// schema types keep working without changing every `toJson` site.
  static Uint8List encode(Map<String, dynamic> map) {
    final payload = msgpack.serialize(_jsonReady(map));
    if (payload.lengthInBytes > maxPayloadBytes) {
      throw ArgumentError('IPC payload too large: ${payload.lengthInBytes} > $maxPayloadBytes');
    }

    final frame = Uint8List(headerSize + payload.lengthInBytes);
    frame[0] = magic0;
    frame[1] = magic1;
    frame[2] = version;
    ByteData.sublistView(frame, 3, 7).setUint32(0, payload.lengthInBytes);
    frame.setRange(headerSize, frame.length, payload);
    return frame;
  }

  /// Decodes a MessagePack payload into a string-keyed map suitable for
  /// existing `fromJson` factories.
  static Map<String, dynamic> decodePayload(Uint8List payload) {
    final decoded = msgpack.deserialize(payload);
    return _asStringKeyedMap(decoded);
  }
}

/// Accumulates byte chunks and yields complete [IpcCodec] frames.
final class IpcFrameBuffer {
  Uint8List _buf = Uint8List(0);
  int _length = 0;

  /// Feeds [chunk] and returns every complete payload decoded so far.
  List<Map<String, dynamic>> push(List<int> chunk) {
    if (chunk.isEmpty) return const [];

    _ensureCapacity(_length + chunk.length);
    _buf.setRange(_length, _length + chunk.length, chunk);
    _length += chunk.length;

    final out = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      if (_length - offset < IpcCodec.headerSize) break;

      final b0 = _buf[offset];
      final b1 = _buf[offset + 1];
      final ver = _buf[offset + 2];
      if (b0 != IpcCodec.magic0 || b1 != IpcCodec.magic1) {
        throw FormatException(
          'Invalid IPC magic (expected ZN), got '
          '0x${b0.toRadixString(16)} 0x${b1.toRadixString(16)} '
          '(stale worker still speaking JSON?)',
          _buf,
          offset,
        );
      }
      if (ver != IpcCodec.version) {
        throw FormatException(
          'Unsupported IPC version $ver (expected ${IpcCodec.version})',
          _buf,
          offset,
        );
      }

      final payloadLen = ByteData.sublistView(_buf, offset + 3, offset + 7).getUint32(0);
      if (payloadLen > IpcCodec.maxPayloadBytes) {
        throw FormatException(
          'IPC payload length $payloadLen exceeds max ${IpcCodec.maxPayloadBytes}',
          _buf,
          offset,
        );
      }

      final frameEnd = offset + IpcCodec.headerSize + payloadLen;
      if (_length < frameEnd) break;

      final payload = Uint8List.sublistView(_buf, offset + IpcCodec.headerSize, frameEnd);
      out.add(IpcCodec.decodePayload(payload));
      offset = frameEnd;
    }

    if (offset > 0) {
      final remain = _length - offset;
      if (remain > 0) {
        final next = Uint8List(remain);
        next.setRange(0, remain, _buf, offset);
        _buf = next;
      } else {
        _buf = Uint8List(0);
      }
      _length = remain;
    }

    return out;
  }

  void _ensureCapacity(int needed) {
    if (_buf.length >= needed) return;
    var cap = _buf.isEmpty ? 256 : _buf.length;
    while (cap < needed) {
      cap *= 2;
    }
    final next = Uint8List(cap);
    if (_length > 0) {
      next.setRange(0, _length, _buf);
    }
    _buf = next;
  }

  /// Drops any partial frame (call when the peer process is replaced).
  void clear() {
    _buf = Uint8List(0);
    _length = 0;
  }
}

Map<String, dynamic> _asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, nested) => MapEntry(key, _deepConvert(nested)));
  }
  if (value is Map) {
    return {for (final entry in value.entries) entry.key.toString(): _deepConvert(entry.value)};
  }
  throw FormatException('IPC payload must be a map, got ${value.runtimeType}');
}

Object? _deepConvert(Object? value) {
  if (value is Map) {
    return _asStringKeyedMap(value);
  }
  if (value is List) {
    return [for (final item in value) _deepConvert(item)];
  }
  return value;
}

/// Same conversion [JsonEncoder] applies: primitives, maps, lists, else
/// `object.toJson()` recursively.
Object? _jsonReady(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Uint8List) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): _jsonReady(entry.value),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) _jsonReady(item)];
  }

  try {
    final dynamic object = value;
    return _jsonReady(object.toJson());
  } on NoSuchMethodError {
    throw FormatException("Don't know how to serialize ${value.runtimeType}");
  }
}
