import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/target_os.dart';
import 'package:zonai/src/domain/versions.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// Talking to GitHub's release API is retried when the failure is usually
/// transient, and a failure says what GitHub answered.
///
/// Reported from a deploy on v0.10.2: `zonai build` for linux/arm64 failed
/// twice with "Failed to download binary for zonai-linux-arm64.zip", then
/// worked on the next run with nothing changed. The message carried no
/// status, so a 403, a 5xx and a rate limit all looked the same, and nothing
/// retried.
void main() {
  const assetUrl =
      'https://api.github.com/repos/mrgnhnt96/zonai/releases/assets/1';
  final releaseJson = jsonEncode({
    'tag_name': 'v0.10.2',
    'assets': [
      {'name': 'zonai-linux-arm64.zip', 'url': assetUrl},
    ],
  });

  late List<String> requests;
  setUp(() => requests = []);

  /// Answers each URL from its own queue of replies; the last one repeats.
  MockClient github(Map<String, List<http.Response Function()>> replies) {
    final served = <String, int>{};
    return MockClient((request) async {
      final url = request.url.toString();
      requests.add(url);
      final queue = replies[url];
      if (queue == null) return http.Response('not found', 404);
      final i = served.update(url, (n) => n + 1, ifAbsent: () => 0);
      return queue[i < queue.length ? i : queue.length - 1]();
    });
  }

  Future<void> download(MockClient client) => http.runWithClient(
    () => runScoped(
      () => Versions(retryDelay: (_) => Duration.zero).downloadBinary(
        version: '0.10.2',
        targetDestination: '/unused',
        targetOs: TargetOs.linux,
        targetArch: Arch.arm64,
      ),
      values: {loggerProvider.overrideWith(() => Logger(level: .error))},
    ),
    () => client,
  );

  const releaseUrl =
      'https://api.github.com/repos/mrgnhnt96/zonai/releases/tags/v0.10.2';

  test('a 5xx from GitHub is retried, and the call goes through', () async {
    // The lookup fails twice and then answers; the download then fails with
    // a 404, which is not retried. Reaching the download at all is the proof.
    final client = github({
      releaseUrl: [
        () => http.Response('{"message":"Server Error"}', 502),
        () => http.Response('{"message":"Server Error"}', 503),
        () => http.Response(releaseJson, 200),
      ],
      assetUrl: [() => http.Response('{"message":"Not Found"}', 404)],
    });

    await expectLater(download(client), throwsA(anything));

    expect(requests.where((u) => u == releaseUrl), hasLength(3));
    expect(
      requests.where((u) => u == assetUrl),
      hasLength(1),
      reason: 'a 404 is not transient, so it is not retried',
    );
  });

  test('a failed download says what GitHub answered', () async {
    final client = github({
      releaseUrl: [() => http.Response(releaseJson, 200)],
      assetUrl: [() => http.Response('{"message":"Not Found"}\nmore', 404)],
    });

    await expectLater(
      download(client),
      throwsA(
        predicate(
          (Object e) =>
              '$e'.contains('zonai-linux-arm64.zip') &&
              '$e'.contains('HTTP 404') &&
              '$e'.contains('{"message":"Not Found"}') &&
              !'$e'.contains('more'),
        ),
      ),
    );
  });

  test('a download that keeps failing gives up after three attempts', () async {
    final client = github({
      releaseUrl: [() => http.Response(releaseJson, 200)],
      assetUrl: [() => http.Response('bad gateway', 502)],
    });

    await expectLater(
      download(client),
      throwsA(predicate((Object e) => '$e'.contains('HTTP 502'))),
    );
    expect(requests.where((u) => u == assetUrl), hasLength(3));
  });

  test('a 429 is retried', () async {
    final client = github({
      releaseUrl: [
        () => http.Response('slow down', 429),
        () => http.Response(releaseJson, 200),
      ],
      assetUrl: [() => http.Response('gone', 410)],
    });

    await expectLater(download(client), throwsA(anything));
    expect(requests.where((u) => u == releaseUrl), hasLength(2));
  });

  test('a dropped connection is retried', () async {
    var calls = 0;
    final client = MockClient((request) async {
      requests.add(request.url.toString());
      if (request.url.toString() == releaseUrl && calls++ == 0) {
        throw http.ClientException('Connection reset by peer');
      }
      if (request.url.toString() == releaseUrl) {
        return http.Response(releaseJson, 200);
      }
      return http.Response('gone', 410);
    });

    await expectLater(download(client), throwsA(anything));
    expect(requests.where((u) => u == releaseUrl), hasLength(2));
  });

  test(
    'a rate-limit 403 says so, names the token, and is not retried',
    () async {
      final client = github({
        releaseUrl: [
          () => http.Response(
            '{"message":"API rate limit exceeded"}',
            403,
            headers: {'x-ratelimit-remaining': '0'},
          ),
        ],
      });

      await expectLater(
        download(client),
        throwsA(
          predicate(
            (Object e) =>
                '$e'.contains('HTTP 403') &&
                '$e'.contains('rate limit') &&
                '$e'.contains('GITHUB_TOKEN'),
          ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );
}
