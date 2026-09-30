import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/utils/compile_coalescer.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main() {
  late int calls;
  late int inFlight;
  late int peak;
  late List<Completer<void>> running;

  setUp(() {
    calls = 0;
    inFlight = 0;
    peak = 0;
    running = [];
  });

  /// A compile that stays running until the test completes it.
  Future<void> compile() async {
    calls++;
    inFlight++;
    if (inFlight > peak) peak = inFlight;
    final done = Completer<void>();
    running.add(done);
    await done.future;
    inFlight--;
  }

  void inScope(void Function(FakeAsync async) body) => runScoped(
    () => fakeAsync(body),
    values: {loggerProvider.overrideWith(() => Logger(level: .error))},
  );

  test('a burst of triggers is one compile', () {
    inScope((async) {
      final coalescer = CompileCoalescer(compile, label: 'rules');
      for (var i = 0; i < 14; i++) {
        coalescer.trigger();
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(calls, 0, reason: 'still inside the debounce');

      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 1);
    });
  });

  test('a trigger during a compile runs exactly one follow-up after it', () {
    inScope((async) {
      final coalescer = CompileCoalescer(compile, label: 'rules');
      coalescer.trigger();
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 1);

      // Several triggers while the first compile is still running.
      for (var i = 0; i < 5; i++) {
        coalescer.trigger();
        async.elapse(const Duration(milliseconds: 400));
      }
      expect(calls, 1, reason: 'nothing starts while one is running');

      running.single.complete();
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(calls, 2, reason: 'one follow-up, not five');
      expect(peak, 1);

      running.last.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      expect(calls, 2, reason: 'and nothing after it');
    });
  });

  test('cancel drops a pending compile and ignores later triggers', () {
    inScope((async) {
      final coalescer = CompileCoalescer(compile, label: 'rules');
      coalescer.trigger();
      coalescer.cancel();
      coalescer.trigger();
      async.elapse(const Duration(seconds: 1));

      expect(calls, 0);
    });
  });

  test('a failing compile does not stop later ones', () {
    inScope((async) {
      var attempts = 0;
      final coalescer = CompileCoalescer(() async {
        attempts++;
        throw StateError('compile failed');
      }, label: 'rules');

      coalescer.trigger();
      async.elapse(const Duration(milliseconds: 300));
      coalescer.trigger();
      async.elapse(const Duration(milliseconds: 300));

      expect(attempts, 2);
    });
  });
}
