import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/serve.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// The interlock that makes the predictable-challenge hook safe to keep:
/// `ZONAI_INSECURE_TEST_MODE` can be set for a test harness, and `zonai serve`
/// will not start while it is.
///
/// Borrowed wholesale from `help_test.dart`, including why: the scope
/// registers only `args` and `logger`, so a `serve()` that gets *past* the
/// refusal fails here by throwing on an unregistered provider rather than by
/// quietly booting a server with the backdoor open. The absence of the guard
/// cannot make this test pass.
class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

Future<({int exitCode, String output})> _serve(Args args) async {
  final sink = _CapturingSink();

  final exitCode = await runScoped(
    serve,
    values: {
      argsProvider.overrideWith(() => args),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
    },
  );

  return (exitCode: exitCode, output: sink.text);
}

void main() {
  group('serve refuses to start under ZONAI_INSECURE_TEST_MODE', () {
    tearDown(() => debugInsecureTestMode = null);

    test('exits non-zero, without touching anything else', () async {
      debugInsecureTestMode = true;

      final result = await _serve(Args(args: const {}));

      expect(result.exitCode, isNot(0));
      expect(result.output, contains(kInsecureTestModeVariable));
      expect(
        result.output,
        contains('will not start'),
        reason: 'the message must say what happened, not just warn',
      );
      expect(
        result.output,
        contains(kInsecureTestOtp),
        reason:
            'naming the fixed OTP makes the consequence concrete for whoever '
            'is reading the failure',
      );
    });

    test('--help still works, so the flags stay readable', () async {
      debugInsecureTestMode = true;

      final result = await _serve(Args(args: const {'help': true}));

      expect(result.output, contains('Usage: zonai serve'));
    });

    // The control: with the mode off, `serve` gets past the refusal and
    // reaches `ensureProjectInitialized`, which throws on the unregistered
    // `fs` provider in this scope. That throw is the proof the guard above is
    // what stopped it, and not something else.
    test('with the mode off, serve proceeds past this point', () async {
      debugInsecureTestMode = false;

      await expectLater(_serve(Args(args: const {})), throwsA(anything));
    });
  });
}
