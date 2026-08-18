// Compares a stress run against the calibrated baseline in `thresholds.json`
// and exits non-zero on a REGRESSION.
//
// It gates error rate and NOT p99 latency. That is a measured decision, not an
// oversight: across the three calibration runs the p99 spread was 139% at the
// median and 2178% at the worst cell, while the error rate moved 0.00
// percentage points at the median and 25 of 30 cells were exactly 0.00% in all
// three. A p99 gate would flap, and a flapping gate gets muted -- which is
// worse than no gate at all. p99 is printed for trend, never asserted.
//
//   dart run bin/check_thresholds.dart results/nightly.json
//
// Exit codes: 0 pass, 1 regression, 2 bad usage/missing cell.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: check_thresholds.dart <run.json> [thresholds.json]');
    exit(2);
  }
  final runFile = File(args[0]);
  final baseFile = File(args.length > 1 ? args[1] : 'thresholds.json');
  for (final f in [runFile, baseFile]) {
    if (!f.existsSync()) {
      stderr.writeln('missing file: ${f.path}');
      exit(2);
    }
  }

  final base = jsonDecode(baseFile.readAsStringSync()) as Map<String, dynamic>;
  final cells = base['cells'] as Map<String, dynamic>;
  final tolerance =
      (base['policy']
              as Map<String, dynamic>)['toleranceAbsolutePercentagePoints']
          as num;
  final run = jsonDecode(runFile.readAsStringSync()) as List<dynamic>;

  final regressions = <String>[];
  final missing = <String>[];
  final knownBad = <String>[];
  var checked = 0;

  for (final raw in run) {
    final e = raw as Map<String, dynamic>;
    final key = '${e['scenario']}@${e['concurrency']}';
    final cell = cells[key] as Map<String, dynamic>?;
    if (cell == null) {
      missing.add(key);
      continue;
    }
    checked++;
    final observed = (e['errorRate'] as num) * 100;
    final baseline = cell['errorRatePercentBaseline'] as num;
    final ceiling = baseline + tolerance;
    final p99 = (e['latencyMs'] as Map<String, dynamic>)['p99'];

    final over = observed > ceiling;
    final marker = over
        ? 'FAIL'
        : (cell['knownBad'] == true ? 'known-bad' : 'ok');
    if (cell['knownBad'] == true && !over) knownBad.add(key);
    stdout.writeln(
      '${marker.padRight(9)} ${key.padRight(20)} '
      'err ${observed.toStringAsFixed(2)}% '
      '(baseline ${baseline.toStringAsFixed(2)}%, ceiling ${ceiling.toStringAsFixed(2)}%)  '
      'p99 ${p99}ms (not gated)',
    );
    if (over) {
      regressions.add(
        '$key: error rate ${observed.toStringAsFixed(2)}% exceeds '
        '${ceiling.toStringAsFixed(2)}% (baseline ${baseline.toStringAsFixed(2)}% '
        '+ ${tolerance}pp tolerance)',
      );
    }
  }

  stdout.writeln('\nchecked $checked cell(s) against ${baseFile.path}');

  // A cell in the baseline that the run never produced is NOT a pass. Silence
  // where a measurement was expected is the failure mode this exists to catch.
  final produced = {
    for (final raw in run) '${(raw as Map)['scenario']}@${raw['concurrency']}',
  };
  final absent = cells.keys.where((k) => !produced.contains(k)).toList();

  if (knownBad.isNotEmpty) {
    stdout.writeln(
      'known-bad and still failing at the SAME rate (recorded, not gated): '
      '${knownBad.join(', ')}',
    );
    stdout.writeln(
      '  These are the write-queue saturation cliff. They are baselined so the gate is '
      'usable today; they are NOT thereby acceptable. See README "Thresholds".',
    );
  }
  if (missing.isNotEmpty) {
    stdout.writeln('NOT CHECKED -- not in the baseline: ${missing.join(', ')}');
  }
  if (absent.isNotEmpty) {
    stderr.writeln(
      'MISSING -- baseline expects these and the run produced none: '
      '${absent.join(', ')}',
    );
    exit(1);
  }
  if (regressions.isEmpty) {
    stdout.writeln('PASS -- no error-rate regression.');
    exit(0);
  }
  stderr.writeln('\nREGRESSION:');
  for (final r in regressions) {
    stderr.writeln('  - $r');
  }
  exit(1);
}
