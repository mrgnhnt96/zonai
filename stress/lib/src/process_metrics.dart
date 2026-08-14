// Samples a process's RSS and CPU% via `ps`. There's no vm_service wired
// into zonai and adding one is out of scope for a throwaway investigation
// script, so this shells out the same way the rest of the harness already
// does (harness_setup.dart's `_run`/`Process.start`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProcessSample {
  const ProcessSample({
    required this.elapsed,
    required this.rssKb,
    required this.cpuPercent,
  });

  /// Time since sampling started.
  final Duration elapsed;

  /// Resident set size in KB, as reported by `ps -o rss=`.
  final int rssKb;

  /// CPU percent, as reported by `ps -o pcpu=` (can exceed 100 on multiple
  /// cores).
  final double cpuPercent;

  String toCsvRow() =>
      '${elapsed.inMilliseconds},$rssKb,${cpuPercent.toStringAsFixed(1)}';

  static const csvHeader = 'elapsed_ms,rss_kb,cpu_percent';
}

/// Samples [pid]'s RSS/CPU every [interval] until [stop] completes, or until
/// [pid] exits on its own.
///
/// Spawns a single long-lived `bash -c 'while ...; do ps ...; sleep ...; done'`
/// loop rather than calling `Process.run('ps', ...)` fresh every tick: a
/// harness that's also churning through dozens of concurrent `HttpClient`
/// sockets (see stream_scenarios.dart) makes repeated fork/exec of a brand
/// new `ps` process from *this* process flaky -- `ps` intermittently (and
/// under sustained load, persistently) comes back with empty output and a
/// non-zero exit code even though the target process is provably still
/// alive (confirmed by polling the same real server process with no
/// concurrent socket load, where every single tick succeeds). Forking the
/// shell loop once up front and having *it* re-exec `ps` on a stable,
/// otherwise-idle process sidesteps that contention entirely.
Stream<ProcessSample> sampleProcess(
  int pid, {
  Duration interval = const Duration(seconds: 1),
  required Future<void> stop,
}) {
  late StreamController<ProcessSample> controller;
  Process? shellProcess;
  StreamSubscription<String>? outSub;
  final stopwatch = Stopwatch()..start();

  Future<void> start() async {
    final intervalSeconds = interval.inMilliseconds / 1000.0;
    shellProcess = await Process.start('bash', [
      '-c',
      'while kill -0 $pid 2>/dev/null; do '
          'ps -o rss=,pcpu= -p $pid 2>/dev/null; '
          'sleep $intervalSeconds; '
          'done',
    ]);
    outSub = shellProcess!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return;
            final parts = trimmed.split(RegExp(r'\s+'));
            if (parts.length < 2) return;
            final rssKb = int.tryParse(parts[0]);
            final cpuPercent = double.tryParse(parts[1]);
            if (rssKb == null || cpuPercent == null || controller.isClosed) {
              return;
            }
            controller.add(
              ProcessSample(
                elapsed: stopwatch.elapsed,
                rssKb: rssKb,
                cpuPercent: cpuPercent,
              ),
            );
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
    unawaited(
      stop.then((_) {
        shellProcess?.kill();
      }),
    );
  }

  controller = StreamController<ProcessSample>(
    onListen: () => unawaited(start()),
    onCancel: () {
      outSub?.cancel();
      shellProcess?.kill();
    },
  );
  return controller.stream;
}

/// Growth-rate summary over a series of samples, for a printed report.
class LeakSummary {
  const LeakSummary({
    required this.startRssKb,
    required this.endRssKb,
    required this.peakRssKb,
    required this.durationMinutes,
  });

  factory LeakSummary.fromSamples(List<ProcessSample> samples) {
    if (samples.isEmpty) {
      return const LeakSummary(
        startRssKb: 0,
        endRssKb: 0,
        peakRssKb: 0,
        durationMinutes: 0,
      );
    }
    return LeakSummary(
      startRssKb: samples.first.rssKb,
      endRssKb: samples.last.rssKb,
      peakRssKb: samples.map((s) => s.rssKb).reduce((a, b) => a > b ? a : b),
      durationMinutes: samples.last.elapsed.inSeconds / 60.0,
    );
  }

  final int startRssKb;
  final int endRssKb;
  final int peakRssKb;
  final double durationMinutes;

  double get growthKb => (endRssKb - startRssKb).toDouble();

  double get growthKbPerMinute =>
      durationMinutes <= 0 ? 0 : growthKb / durationMinutes;

  @override
  String toString() =>
      'start=${startRssKb}KB end=${endRssKb}KB peak=${peakRssKb}KB '
      'growth=${growthKb.toStringAsFixed(0)}KB over '
      '${durationMinutes.toStringAsFixed(1)}min '
      '(${growthKbPerMinute.toStringAsFixed(1)}KB/min)';
}
