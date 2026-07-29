import 'dart:async';
import 'dart:io';

import 'stats.dart';

/// Sends one request using [client] and reports how it went.
typedef RequestSender = Future<RequestResult> Function(HttpClient client);

/// Drives [concurrency] workers in a tight loop against [sender] for
/// [duration], after an untimed [warmup] period meant to let worker
/// subprocesses, JIT-free but still cold caches, and sqlite pages settle.
class LoadRunner {
  LoadRunner();

  Future<ScenarioStats> run({
    required String scenario,
    required RequestSender sender,
    required int concurrency,
    required Duration duration,
    Duration warmup = const Duration(seconds: 1),
  }) async {
    final client = HttpClient()..maxConnectionsPerHost = concurrency;
    final results = <RequestResult>[];
    final stopwatch = Stopwatch();

    try {
      if (warmup > Duration.zero) {
        await _drive(
          client: client,
          sender: sender,
          concurrency: concurrency,
          runFor: warmup,
          onResult: (_) {},
        );
      }

      stopwatch.start();
      await _drive(
        client: client,
        sender: sender,
        concurrency: concurrency,
        runFor: duration,
        onResult: results.add,
      );
      stopwatch.stop();
    } finally {
      client.close(force: true);
    }

    return ScenarioStats(
      scenario: scenario,
      concurrency: concurrency,
      wallTime: stopwatch.elapsed,
      results: results,
    );
  }

  Future<void> _drive({
    required HttpClient client,
    required RequestSender sender,
    required int concurrency,
    required Duration runFor,
    required void Function(RequestResult) onResult,
  }) async {
    final deadline = DateTime.now().add(runFor);
    await Future.wait(
      List.generate(concurrency, (_) async {
        while (DateTime.now().isBefore(deadline)) {
          onResult(await sender(client));
        }
      }),
    );
  }
}
