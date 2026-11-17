import 'dart:async';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/stdin.dart';
import 'package:zonai/src/domain/clean_up.dart';
import 'package:zonai/src/domain/keyboard_input.dart';
import 'package:zonai/src/domain/stdin.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// Records whether anything subscribed to stdin, which is what closes fd 0
/// once a non-terminal stdin reaches EOF.
class _FakeStdin extends Stdin {
  _FakeStdin({required this.hasTerminal});

  @override
  final bool hasTerminal;

  final controller = StreamController<List<int>>.broadcast();
  var streamRead = false;

  @override
  Stream<List<int>> get stream {
    streamRead = true;
    return controller.stream;
  }

  @override
  set echoMode(bool value) {}

  @override
  set lineMode(bool value) {}
}

void main() {
  group(KeyboardInput, () {
    T run<T>(_FakeStdin fake, T Function() body) => runScoped(
      body,
      values: {
        argsProvider.overrideWith(() => const Args(args: {})),
        cleanUpProvider.overrideWith(CleanUp.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        stdinProvider.overrideWith(() => fake),
      },
    );

    test('watch() leaves a non-terminal stdin unread', () {
      // Reading it would hit EOF and close fd 0, and on Dart 3.14 macOS every
      // worker spawned afterwards starts with no stdin.
      final fake = _FakeStdin(hasTerminal: false);

      run(fake, () => KeyboardInput().watch());

      expect(fake.streamRead, isFalse);
    });

    test('watch() listens for hotkeys on a terminal', () async {
      final fake = _FakeStdin(hasTerminal: true);
      final pressed = Completer<void>();

      await run(fake, () async {
        KeyboardInput()
          ..onKey('r', pressed.complete)
          ..watch();
        fake.controller.add('r'.codeUnits);

        await expectLater(pressed.future, completes);
      });

      expect(fake.streamRead, isTrue);
    });
  });
}
