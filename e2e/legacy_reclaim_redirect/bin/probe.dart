// Drives the harness in `lib/probe_server.dart` and prints what the SERVER
// received, which is the only instrument that answers this question honestly:
// a client can only report what it meant to send.
//
//   dart run bin/probe.dart --code 302          # the dart:io leg
//   dart run bin/probe.dart --code 307
//   dart run bin/probe.dart --code 302 --serve  # the browser leg
//
// `--serve` compiles `web/browser_probe.dart` to JavaScript, serves it, and
// waits for a real browser to open the printed URL. Pass `--browser <path>`
// to launch one; without it the URL is printed and the harness waits, because
// WHICH browser ran is part of the evidence and must not be hidden.
// `--headless` adds Chrome's headless flags to that launch.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:revali_client/revali_client.dart';
import 'package:zonai_legacy_reclaim_redirect/probe_server.dart';

class _NoStorage implements Storage {
  const _NoStorage();

  @override
  Future<Object?> operator [](String key) async => null;

  @override
  Future<void> save(String key, Object? value) async {}

  @override
  Future<void> saveAll(Map<String, Object?> values) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> remove(String key) async {}
}

Future<void> main(List<String> args) async {
  final code = int.parse(_flag(args, '--code') ?? '302');
  final serve = args.contains('--serve');

  final js = serve ? await _compileBrowserProbe() : null;
  final probe = await ProbeServer.start(redirectCode: code, browserProbeJs: js);

  stdout.writeln('redirect code under test: $code');
  stdout.writeln('server: ${probe.baseUri}');

  if (serve) {
    final browser = _flag(args, '--browser');
    Process? process;

    if (browser == null) {
      stdout.writeln('open ${probe.baseUri} in a real browser');
    } else {
      final version = await Process.run(browser, ['--version']);
      stdout.writeln('browser: ${'${version.stdout}'.trim()}');
      stdout.writeln('browser path: $browser');
      process = await Process.start(browser, [
        if (args.contains('--headless')) ...['--headless=new', '--disable-gpu'],
        '--no-first-run',
        '--no-default-browser-check',
        '--user-data-dir='
            '${Directory.systemTemp.createTempSync('legacy-reclaim-chrome').path}',
        '${probe.baseUri}',
      ]);
    }

    final report = await probe.browserReport.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => '<no report: the browser never posted back>',
    );
    stdout.writeln('client (browser) reported: $report');
    process?.kill();
  } else {
    final client = RevaliClient(
      storage: const _NoStorage(),
      baseUrl: '${probe.baseUri}',
    );

    try {
      final response = await client.request(
        method: 'POST',
        path: ProbeServer.legacyPath,
        headers: {'authorization': 'probe'},
      );
      final body = await response.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      stdout.writeln('client (dart:io) reported: ${response.statusCode} $body');
    } catch (e) {
      stdout.writeln('client (dart:io) reported: ${e.runtimeType}: $e');
    }
  }

  stdout.writeln('--- server received ---');
  for (final request in probe.received) {
    stdout.writeln(request);
  }

  await probe.close();
}

String? _flag(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Future<String> _compileBrowserProbe() async {
  final out = Directory.systemTemp.createTempSync('legacy-reclaim-probe');
  final target = '${out.path}/probe.js';

  final result = await Process.run('dart', [
    'compile',
    'js',
    '-o',
    target,
    'web/browser_probe.dart',
  ]);

  if (result.exitCode != 0) {
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    throw StateError('dart compile js failed (${result.exitCode})');
  }

  return File(target).readAsStringSync();
}
