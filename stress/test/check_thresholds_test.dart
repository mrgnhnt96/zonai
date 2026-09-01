// Runs `bin/check_thresholds.dart` as a subprocess against small synthetic
// baselines and results, the way stress-nightly.yml's gate step runs it. The
// script is a `main` with no library surface -- and `stress/lib/` is the load
// harness, not the gate -- so the gate is exercised through its real
// interface: two JSON files in, stdout/stderr and an exit code out.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('check_thresholds_test_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<_Gate> gate({
    required Map<String, dynamic> cells,
    required List<Map<String, dynamic>> run,
  }) async {
    final base = File('${tmp.path}/thresholds.json')
      ..writeAsStringSync(
        jsonEncode({
          'policy': {'toleranceAbsolutePercentagePoints': 2.0},
          'cells': cells,
        }),
      );
    final results = File('${tmp.path}/run.json')
      ..writeAsStringSync(jsonEncode(run));
    final proc = await Process.run(Platform.resolvedExecutable, [
      'bin/check_thresholds.dart',
      results.path,
      base.path,
    ]);
    return _Gate(proc.exitCode, proc.stdout as String, proc.stderr as String);
  }

  group('okPerSec', () {
    // 20 successes over 4s = 5.0 ok/s.
    final cell = {
      'gate': 'okPerSec',
      'okPerSecFloor': 4,
      'okPerSecObserved': [6.0, 9.5, 7.0],
      'errorRatePercentBaseline': 98.0,
    };

    test('passes when ok/s is at or above the floor', () async {
      final g = await gate(
        cells: {'create@100': cell},
        run: [_result('create', 100, total: 1020, errors: 1000, wallMs: 4000)],
      );
      expect(g.exitCode, 0, reason: g.stderr);
      expect(
        g.stdout,
        contains('ok/s 5.0 (floor 4.0 = worst 6.0 - 1 spread 3.5)'),
      );
      expect(g.stdout, contains('checked 1 cell(s)'));
    });

    test('fails when ok/s drops below the floor', () async {
      // 12 successes over 4s = 3.0 ok/s, under a floor of 4.
      final g = await gate(
        cells: {'create@100': cell},
        run: [_result('create', 100, total: 1012, errors: 1000, wallMs: 4000)],
      );
      expect(g.exitCode, 1);
      expect(g.stdout, contains('FAIL        create@100'));
      expect(g.stderr, contains('create@100: ok/s 3.0 below floor 4.0'));
    });

    test('error rate does not gate an okPerSec cell', () async {
      // 99.9% errors, far above baseline + tolerance, but ok/s is 5.0 >= 4.
      final g = await gate(
        cells: {'create@100': cell},
        run: [
          _result('create', 100, total: 20000, errors: 19980, wallMs: 4000),
        ],
      );
      expect(g.exitCode, 0, reason: g.stderr);
      expect(g.stdout, contains('err 99.90% (not gated)'));
    });

    test('a floor at or below zero is refused as a dead gate', () async {
      final g = await gate(
        cells: {
          'create@100': {...cell, 'okPerSecFloor': 0},
        },
        run: [_result('create', 100, total: 1020, errors: 1000, wallMs: 4000)],
      );
      expect(g.exitCode, 1);
      expect(g.stdout, contains('DEAD-GATE   create@100'));
      expect(g.stdout, contains('checked 0 cell(s)'));
      expect(g.stderr, contains('DEAD GATE'));
      expect(g.stderr, contains('okPerSecFloor 0.0000'));
    });

    test('a missing floor is refused as a dead gate', () async {
      final g = await gate(
        cells: {
          'create@100': {'gate': 'okPerSec', 'errorRatePercentBaseline': 98.0},
        },
        run: [_result('create', 100, total: 1020, errors: 1000, wallMs: 4000)],
      );
      expect(g.exitCode, 1);
      expect(g.stderr, contains('no okPerSecFloor'));
    });
  });

  group('none', () {
    test('is printed report-only and excluded from the checked count', () async {
      final g = await gate(
        cells: {
          'delete@100': {'gate': 'none', 'errorRatePercentBaseline': 99.5},
          'list@1': {'errorRatePercentBaseline': 0.0},
        },
        run: [
          // 100% errors and zero throughput: would fail either real gate.
          _result('delete', 100, total: 5000, errors: 5000, wallMs: 5000),
          _result('list', 1, total: 100, errors: 0, wallMs: 5000),
        ],
      );
      expect(g.exitCode, 0, reason: g.stderr);
      expect(g.stdout, contains('report-only delete@100'));
      expect(g.stdout, contains('checked 1 cell(s)'));
      expect(
        g.stdout,
        contains(
          'report-only (measured, NOT checked, not in the count above): delete@100',
        ),
      );
    });

    test('still fails when the run did not produce the cell', () async {
      final g = await gate(
        cells: {
          'delete@100': {'gate': 'none', 'errorRatePercentBaseline': 99.5},
        },
        run: [_result('list', 1, total: 100, errors: 0, wallMs: 5000)],
      );
      expect(g.exitCode, 1);
      expect(g.stderr, contains('MISSING'));
      expect(g.stderr, contains('delete@100'));
    });
  });

  group('errorRate', () {
    test('an absent gate field still gates error rate', () async {
      // 5% errors against a 0% baseline + 2pp default tolerance.
      final g = await gate(
        cells: {
          'list@1': {'errorRatePercentBaseline': 0.0},
        },
        run: [_result('list', 1, total: 1000, errors: 50, wallMs: 5000)],
      );
      expect(g.exitCode, 1);
      expect(g.stdout, contains('FAIL        list@1'));
      expect(g.stderr, contains('error rate 5.00% exceeds 2.00%'));
    });

    test('an explicit errorRate gate behaves the same as absent', () async {
      final g = await gate(
        cells: {
          'list@1': {'gate': 'errorRate', 'errorRatePercentBaseline': 0.0},
        },
        run: [_result('list', 1, total: 1000, errors: 10, wallMs: 5000)],
      );
      expect(g.exitCode, 0, reason: g.stderr);
      expect(g.stdout, contains('ok          list@1'));
      expect(g.stdout, contains('ceiling 2.00% = +2.0pp default'));
      expect(g.stdout, contains('checked 1 cell(s)'));
    });

    test('a ceiling at or above 100 is still refused as a dead gate', () async {
      final g = await gate(
        cells: {
          'delete@100': {'errorRatePercentBaseline': 99.5},
        },
        run: [_result('delete', 100, total: 1000, errors: 995, wallMs: 5000)],
      );
      expect(g.exitCode, 1);
      expect(g.stdout, contains('DEAD-GATE   delete@100'));
      expect(g.stderr, contains('ceiling 101.5000%'));
    });
  });

  test(
    'an unknown gate kind is refused rather than checked as nothing',
    () async {
      final g = await gate(
        cells: {
          'list@1': {'gate': 'p99', 'errorRatePercentBaseline': 0.0},
        },
        run: [_result('list', 1, total: 100, errors: 0, wallMs: 5000)],
      );
      expect(g.exitCode, 1);
      expect(g.stderr, contains('unknown gate kind "p99"'));
      expect(g.stdout, contains('checked 0 cell(s)'));
    },
  );

  test('the committed thresholds.json names no dead gate', () async {
    // Every cell in the real baseline, fed a run that produces each of them
    // cleanly, so a floor <= 0 or a ceiling >= 100 checked into the file is
    // caught here rather than on the next Monday run.
    final base =
        jsonDecode(File('thresholds.json').readAsStringSync())
            as Map<String, dynamic>;
    final cells = (base['cells'] as Map<String, dynamic>).keys;
    final run = [
      for (final key in cells)
        _result(
          key.split('@')[0],
          int.parse(key.split('@')[1]),
          total: 1000,
          errors: 0,
          wallMs: 5000,
        ),
    ];
    final proc = await Process.run(Platform.resolvedExecutable, [
      'bin/check_thresholds.dart',
      (File('${tmp.path}/run.json')..writeAsStringSync(jsonEncode(run))).path,
      'thresholds.json',
    ]);
    expect(proc.exitCode, 0, reason: '${proc.stdout}\n${proc.stderr}');
    expect(
      proc.stdout,
      contains('ok/s 200.0 (floor 19.0 = worst 35.3 - 1 spread 16.1)'),
    );
    expect(proc.stdout, contains('report-only delete@100'));
    expect(proc.stdout, contains('checked ${cells.length - 1} cell(s)'));
  });
}

class _Gate {
  const _Gate(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

Map<String, dynamic> _result(
  String scenario,
  int concurrency, {
  required int total,
  required int errors,
  required int wallMs,
}) {
  return {
    'scenario': scenario,
    'concurrency': concurrency,
    'wallTimeMs': wallMs,
    'total': total,
    'errors': errors,
    'requestsPerSecond': total / wallMs * 1000,
    'errorRate': total == 0 ? 0.0 : errors / total,
    'latencyMs': {'p50': 1.0, 'p90': 2.0, 'p95': 3.0, 'p99': 4.0},
  };
}
