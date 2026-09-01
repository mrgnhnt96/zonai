// Compares a stress run against the calibrated baseline in `thresholds.json`
// and exits non-zero on a REGRESSION.
//
// Every cell names its own gate kind with a `gate` field (README "Thresholds"):
//
//   "errorRate" (the default when the field is absent) -- the cell FAILS when
//       its error rate exceeds `errorRatePercentBaseline` plus a tolerance.
//   "okPerSec" -- the cell FAILS when its successful throughput,
//       (total - errors) / wallTimeMs * 1000, drops below `okPerSecFloor`.
//       This is for the two fully saturated write cells, where the error rate
//       sits at 98-99.6% BY DESIGN and has ~1pp and ~0.2pp of live range before
//       the 100% wall: the error-rate gate scored a 4x throughput IMPROVEMENT
//       as a regression there (run 33546159251).
//   "none" -- report-only. Printed, listed in the summary, NOT checked and NOT
//       counted as checked. delete@100 lives here: it completes exactly 64
//       requests in every run regardless of duration (the end-of-run drain of
//       a queue pinned at `_maxQueuedWrites`), so its ok/s is the queue depth
//       divided by wall time and no gate can stand on it.
//
// No kind gates p99 latency. That is a measured decision, not an oversight:
// across the three calibration runs the p99 spread was 139% at the median and
// 2178% at the worst cell, while the error rate moved 0.00 percentage points
// at the median and 25 of 30 cells were exactly 0.00% in all three. A p99 gate
// would flap, and a flapping gate gets muted -- which is worse than no gate at
// all. p99 is printed for trend, never asserted.
//
//   dart run bin/check_thresholds.dart results/nightly.json
//
// Exit codes: 0 pass, 1 regression or an unusable baseline (a cell the run
// never produced, a cell whose ceiling or floor no run could ever trip, or a
// cell naming a gate kind this file does not know), 2 bad usage/missing file.
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
  // The DEFAULT tolerance. A cell may widen it for itself with
  // `toleranceOverridePP` -- see the loop below and README "Thresholds".
  final defaultTolerance =
      (base['policy']
              as Map<String, dynamic>)['toleranceAbsolutePercentagePoints']
          as num;
  final run = jsonDecode(runFile.readAsStringSync()) as List<dynamic>;

  // A gate that cannot trip is a CONFIGURATION error, not a lenient cell.
  //
  // An error rate is a percentage of requests, so no run can ever measure more
  // than 100%: an errorRate cell with a ceiling at or above 100 passes every
  // time while printing exactly like a live one. Successful throughput cannot
  // be negative, so an okPerSec cell with a floor at or below 0 is the same
  // thing in the other direction. And a `gate` value this file does not know
  // would silently be checked as nothing at all. Same reasoning as the MISSING
  // block at the end of main: a cell that was not really checked is a failure,
  // not a pass. Scanned across the whole baseline rather than only the cells
  // this run produced, because it is a fact about the file and holds whether
  // or not the run reached the cell.
  final unreachable = <String, String>{};
  for (final entry in cells.entries) {
    final cell = entry.value as Map<String, dynamic>;
    final gate = _gateOf(cell);
    switch (gate) {
      case _Gate.errorRate:
        final override = cell['toleranceOverridePP'] as num?;
        final tolerance = override ?? defaultTolerance;
        final baseline = cell['errorRatePercentBaseline'] as num;
        final ceiling = baseline + tolerance;
        if (ceiling >= 100) {
          unreachable[entry.key] =
              'ceiling ${ceiling.toStringAsFixed(4)}% = baseline '
              '${baseline.toStringAsFixed(4)}% + ${tolerance}pp '
              '${override == null ? 'default' : 'override'}';
        }
      case _Gate.okPerSec:
        final floor = cell['okPerSecFloor'] as num?;
        if (floor == null) {
          unreachable[entry.key] = 'gate okPerSec with no okPerSecFloor';
        } else if (floor <= 0) {
          unreachable[entry.key] =
              'okPerSecFloor ${floor.toStringAsFixed(4)} -- successful '
              'throughput cannot drop below 0';
        }
      case _Gate.none:
        break;
      case null:
        unreachable[entry.key] =
            'unknown gate kind "${cell['gate']}" (expected errorRate, '
            'okPerSec or none)';
    }
  }

  final regressions = <String>[];
  final missing = <String>[];
  final knownBad = <String>[];
  final reportOnly = <String>[];
  var checked = 0;

  for (final raw in run) {
    final e = raw as Map<String, dynamic>;
    final key = '${e['scenario']}@${e['concurrency']}';
    final cell = cells[key] as Map<String, dynamic>?;
    if (cell == null) {
      missing.add(key);
      continue;
    }
    final gate = _gateOf(cell);
    final dead = unreachable.containsKey(key);
    final observed = (e['errorRate'] as num) * 100;
    final okPerSec = _okPerSec(e);
    final p99 = (e['latencyMs'] as Map<String, dynamic>)['p99'];

    // `over` stays first so a widened or dead ceiling can never hide a real
    // failure. DEAD-GATE sits above known-bad/ok because both of those read as
    // "this cell was checked", and this one was not. Same for report-only.
    final bool over;
    final String metric;
    final String reason;
    switch (gate) {
      case _Gate.errorRate:
        // A cell whose run-to-run variance genuinely exceeds the global
        // tolerance may name its own, so one wide cell does not force
        // everybody else's gate open. Which one was used is PRINTED, because a
        // widened ceiling catches less and that has to be visible to a reader
        // rather than buried here.
        final baseline = cell['errorRatePercentBaseline'] as num;
        final override = cell['toleranceOverridePP'] as num?;
        final tolerance = override ?? defaultTolerance;
        final toleranceSource = override == null ? 'default' : 'override';
        final ceiling = baseline + tolerance;
        over = observed > ceiling;
        metric =
            'err ${observed.toStringAsFixed(2)}% '
            '(baseline ${baseline.toStringAsFixed(2)}%, '
            'ceiling ${ceiling.toStringAsFixed(2)}% '
            '= +${tolerance}pp $toleranceSource)  '
            'ok/s ${okPerSec.toStringAsFixed(1)} (not gated)';
        reason =
            'error rate ${observed.toStringAsFixed(2)}% exceeds '
            '${ceiling.toStringAsFixed(2)}% (baseline '
            '${baseline.toStringAsFixed(2)}% + ${tolerance}pp '
            '$toleranceSource tolerance)';
      case _Gate.okPerSec:
        // The floor is the cell's own number. What it stands on -- the worst
        // calibration observation and the spread it was pushed down by -- is
        // printed on the line for the same reason the tolerance source is:
        // a reader has to be able to see how much a pass is worth.
        final floor = (cell['okPerSecFloor'] as num?) ?? 0;
        final basis = _floorBasis(cell);
        over = okPerSec < floor;
        metric =
            'ok/s ${okPerSec.toStringAsFixed(1)} '
            '(floor ${floor.toStringAsFixed(1)}$basis)  '
            'err ${observed.toStringAsFixed(2)}% (not gated)';
        reason =
            'ok/s ${okPerSec.toStringAsFixed(1)} below floor '
            '${floor.toStringAsFixed(1)}$basis';
      case _Gate.none:
      case null:
        over = false;
        metric =
            'ok/s ${okPerSec.toStringAsFixed(1)} (not gated)  '
            'err ${observed.toStringAsFixed(2)}% (not gated)';
        reason = '';
    }

    final String marker;
    if (over) {
      marker = 'FAIL';
    } else if (dead) {
      marker = 'DEAD-GATE';
    } else if (gate == _Gate.none) {
      marker = 'report-only';
    } else if (cell['knownBad'] == true) {
      marker = 'known-bad';
    } else {
      marker = 'ok';
    }
    // Only a cell a gate actually stood on counts as checked. A report-only
    // cell was NOT checked, and saying it was is how a gate goes quietly dead.
    if (!dead && gate != _Gate.none && gate != null) checked++;
    if (marker == 'report-only') reportOnly.add(key);
    if (marker == 'known-bad') knownBad.add(key);
    stdout.writeln(
      '${marker.padRight(11)} ${key.padRight(20)} $metric  '
      'p99 ${p99}ms (not gated)',
    );
    if (over) regressions.add('$key: $reason');
  }

  stdout.writeln('\nchecked $checked cell(s) against ${baseFile.path}');

  // A cell in the baseline that the run never produced is NOT a pass. Silence
  // where a measurement was expected is the failure mode this exists to catch.
  // That holds for every gate kind, report-only included: a report-only cell
  // still has to be measured, it is just not asserted.
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
  if (reportOnly.isNotEmpty) {
    stdout.writeln(
      'report-only (measured, NOT checked, not in the count above): '
      '${reportOnly.join(', ')}',
    );
    stdout.writeln(
      '  A cell with gate "none" asserts nothing. Each one says why in its '
      '`calibrationNote`. See README "Thresholds".',
    );
  }
  if (missing.isNotEmpty) {
    stdout.writeln('NOT CHECKED -- not in the baseline: ${missing.join(', ')}');
  }
  if (unreachable.isNotEmpty) {
    stderr.writeln(
      'DEAD GATE -- these cells can never be tripped and were NOT checked:',
    );
    for (final e in unreachable.entries) {
      stderr.writeln('  - ${e.key}: ${e.value}');
    }
    stderr.writeln(
      '  An error rate cannot exceed 100% and a successful throughput cannot '
      'drop below 0, so a ceiling at or above 100% or a floor at or below 0 is '
      'a cell that reports a pass every run while looking exactly like a live '
      'one. Re-express it with a reachable limit -- a toleranceOverridePP that '
      'keeps baseline + tolerance below 100, or an okPerSecFloor above 0 -- or '
      'make it honestly report-only with gate "none". See README "Thresholds".',
    );
  }
  if (absent.isNotEmpty) {
    stderr.writeln(
      'MISSING -- baseline expects these and the run produced none: '
      '${absent.join(', ')}',
    );
  }
  if (unreachable.isNotEmpty || absent.isNotEmpty) {
    exit(1);
  }
  if (regressions.isEmpty) {
    stdout.writeln('PASS -- no regression on any gated cell.');
    exit(0);
  }
  stderr.writeln('\nREGRESSION:');
  for (final r in regressions) {
    stderr.writeln('  - $r');
  }
  exit(1);
}

enum _Gate { errorRate, okPerSec, none }

/// The cell's gate kind, or null for a value this file does not know. An
/// ABSENT field is `errorRate`: every cell calibrated before the field existed
/// keeps exactly the behaviour it had.
_Gate? _gateOf(Map<String, dynamic> cell) {
  final raw = cell['gate'];
  if (raw == null) return _Gate.errorRate;
  return switch (raw) {
    'errorRate' => _Gate.errorRate,
    'okPerSec' => _Gate.okPerSec,
    'none' => _Gate.none,
    _ => null,
  };
}

/// Successful requests per second of wall time. `total - errors` rather than
/// the run's own `requestsPerSecond`, which counts rejected requests too and
/// therefore RISES as a saturated server gets worse at serving.
double _okPerSec(Map<String, dynamic> e) {
  final total = e['total'] as num;
  final errors = e['errors'] as num;
  final wallMs = e['wallTimeMs'] as num;
  if (wallMs <= 0) return 0;
  return (total - errors) / wallMs * 1000;
}

/// ` = worst 35.3 - 1 spread 16.1` when the cell carries its calibration
/// observations, so the arithmetic behind the floor is on the screen; empty
/// when it does not.
String _floorBasis(Map<String, dynamic> cell) {
  final observed = (cell['okPerSecObserved'] as List<dynamic>?)
      ?.cast<num>()
      .toList();
  if (observed == null || observed.isEmpty) return '';
  final worst = observed.reduce((a, b) => a < b ? a : b);
  final best = observed.reduce((a, b) => a > b ? a : b);
  final spread = best - worst;
  return ' = worst ${worst.toStringAsFixed(1)} - 1 spread '
      '${spread.toStringAsFixed(1)}';
}
