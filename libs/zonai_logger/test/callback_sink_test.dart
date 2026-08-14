import 'package:test/test.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main() {
  group('CallbackSink', () {
    test('write() invokes the callback with the object', () {
      final received = <Object?>[];
      final sink = CallbackSink(callback: received.add);

      sink.write('hello');

      expect(received, ['hello']);
    });

    test('writeln() invokes the callback without adding a newline', () {
      // Logger relies on this: it builds its own newlines via writeln calls
      // rather than embedding them, so writeln must not silently append one.
      final received = <Object?>[];
      final sink = CallbackSink(callback: received.add);

      sink.writeln('a line');

      expect(received, ['a line']);
    });

    test('add() decodes bytes with the sink encoding before invoking the callback', () {
      final received = <Object?>[];
      final sink = CallbackSink(callback: received.add);

      sink.add('hi'.codeUnits);

      expect(received, ['hi']);
    });

    test('writeAll() joins with the given separator', () {
      final received = <Object?>[];
      final sink = CallbackSink(callback: received.add);

      sink.writeAll(['a', 'b', 'c'], '-');

      expect(received, ['a-b-c']);
    });

    test('addError() reports the error and, when present, the stack trace', () {
      final received = <Object?>[];
      final sink = CallbackSink(callback: received.add);

      sink.addError(StateError('bad'), StackTrace.empty);

      expect(received, hasLength(2));
      expect(received[0], contains('bad'));
    });
  });
}
