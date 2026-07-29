import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'load_runner.dart';
import 'stats.dart';

final _random = Random();

String _randomToken() =>
    '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

Future<RequestResult> _send(
  HttpClient client,
  String method,
  Uri uri, {
  Map<String, Object?>? body,
  String? bearerToken,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final request = await client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    if (bearerToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    await response.drain<void>();
    stopwatch.stop();

    final success = response.statusCode >= 200 && response.statusCode < 300;
    return RequestResult(
      success: success,
      latency: stopwatch.elapsed,
      statusCode: response.statusCode,
      error: success ? null : 'HTTP ${response.statusCode}',
    );
  } catch (e) {
    stopwatch.stop();
    return RequestResult(
      success: false,
      latency: stopwatch.elapsed,
      error: '$e',
    );
  }
}

Uri _dbListUri(Uri base, {required int limit}) {
  final body = jsonEncode({
    'table': 'items',
    'expand': <String>[],
    'limit': limit,
  });
  return base.replace(path: '/db/list', queryParameters: {'body': body});
}

/// Read-only baseline: list up to [limit] rows from the `items` table.
/// Exercises the rules worker (canList/canView) and a sqlite read.
RequestSender listItems(Uri base, {int limit = 50}) {
  final uri = _dbListUri(base, limit: limit);
  return (client) => _send(client, 'GET', uri);
}

/// Write path: create a row in `items`. Exercises the rules worker
/// (canCreate), any extensions, and a sqlite write + WAL commit.
RequestSender createItem(Uri base) {
  final uri = base.replace(path: '/db');
  return (client) => _send(
    client,
    'POST',
    uri,
    body: {
      'table': 'items',
      'object': {'name': 'stress-${_randomToken()}'},
    },
  );
}

/// Alternates list/create on every call at the given [createRatio]
/// (0.0 = all reads, 1.0 = all writes) to approximate a realistic mix.
RequestSender mixedReadWrite(Uri base, {double createRatio = 0.2}) {
  final read = listItems(base);
  final write = createItem(base);
  return (client) =>
      _random.nextDouble() < createRatio ? write(client) : read(client);
}

/// Auth sign-up: creates a brand new user every call. Exercises password
/// hashing plus the same rules/extension path as any other table write.
RequestSender signUp(Uri base) {
  final uri = base.replace(path: '/auth/sign-up');
  return (client) => _send(
    client,
    'POST',
    uri,
    body: {
      'type': 'signUp',
      'table': 'users',
      'email': 'stress-${_randomToken()}@example.com',
      'password': 'hunter22',
    },
  );
}

/// Auth sign-in against a single pre-seeded account. Exercises password
/// verification (hash comparison) without also paying create overhead.
RequestSender signIn(
  Uri base, {
  required String email,
  required String password,
}) {
  final uri = base.replace(path: '/auth/sign-in');
  return (client) => _send(
    client,
    'POST',
    uri,
    body: {
      'type': 'signIn',
      'table': 'users',
      'email': email,
      'password': password,
    },
  );
}

Future<bool> waitForHealth(
  Uri base, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient();
  final deadline = DateTime.now().add(timeout);
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(base.replace(path: '/health'));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return true;
      } catch (_) {
        // server not up yet
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  } finally {
    client.close(force: true);
  }
}
