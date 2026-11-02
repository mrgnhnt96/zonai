import 'dart:async';
import 'dart:typed_data';

/// Re-chunks a byte stream of back-to-back JSON values so that each chunk it
/// emits is exactly one whole top-level value.
///
/// The server writes each `/db/stream*` message as one JSON object with no
/// separator, and the network splits and joins those writes however it likes:
/// a 3.7 KB message can arrive as 1,015 + 2,753 bytes, and two small messages
/// can arrive in one read. Decoding each read on its own fails on both.
///
/// Values are found by tracking bracket depth outside strings, so only objects
/// and arrays are accepted at the top level. Whitespace between values is
/// skipped. Anything else between values, and a value the stream ends inside
/// of, is reported as a [FormatException] on the output stream; framing picks
/// up again at the next `{` or `[`.
///
/// Every structural byte is ASCII and every byte of a multi-byte UTF-8
/// sequence is 0x80 or above, so splitting on bytes never cuts a character.
class JsonValueFramer extends StreamTransformerBase<List<int>, List<int>> {
  const JsonValueFramer();

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) =>
      Stream.eventTransformed(stream, _FramingSink.new);
}

const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _quote = 0x22;
const _backslash = 0x5C;

bool _isWhitespace(int byte) =>
    byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09;

class _FramingSink implements EventSink<List<int>> {
  _FramingSink(this._out);

  final EventSink<List<int>> _out;
  final _pending = BytesBuilder(copy: true);

  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;
  bool _discarding = false;

  @override
  void add(List<int> chunk) {
    var start = 0;

    for (var i = 0; i < chunk.length; i++) {
      final byte = chunk[i];

      if (_depth == 0) {
        if (byte != _openBrace && byte != _openBracket) {
          if (!_isWhitespace(byte) && !_discarding) {
            _discarding = true;
            _out.addError(
              FormatException(
                'Expected a JSON object or array between stream messages',
                String.fromCharCode(byte),
              ),
            );
          }
          start = i + 1;
          continue;
        }
        _discarding = false;
      }

      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (byte == _backslash) {
          _escaped = true;
        } else if (byte == _quote) {
          _inString = false;
        }
        continue;
      }

      switch (byte) {
        case _quote:
          _inString = true;
        case _openBrace || _openBracket:
          _depth++;
        case _closeBrace || _closeBracket:
          _depth--;
          if (_depth == 0) {
            _pending.add(chunk.sublist(start, i + 1));
            _out.add(_pending.takeBytes());
            start = i + 1;
          }
      }
    }

    if (_depth > 0 && start < chunk.length) {
      _pending.add(chunk.sublist(start));
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _out.addError(error, stackTrace);
  }

  @override
  void close() {
    if (_depth > 0) {
      _out.addError(
        FormatException(
          'Stream ended inside a JSON message '
          '(${_pending.length} bytes never completed)',
        ),
      );
    }
    _out.close();
  }
}
