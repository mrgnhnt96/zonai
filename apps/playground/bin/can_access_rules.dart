import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';

/// Talks to `.zonai/rules/db_rules.exe` with `can_access` requests over one
/// process, matching responses to requests by `id`.
///
/// Run from `apps/playground`:
/// `dart run bin/can_access_rules.dart`
///
/// Sends one JSON line per request with [Request.generateId], flushes before
/// waiting for the matching response so stdin chunks stay one message each
/// (see [MessageHandler.listen]). Responses are newline-terminated JSON lines.
Future<void> main() async {
  final playgroundRoot = File(Platform.script.toFilePath()).parent.parent.path;
  final exePath = '$playgroundRoot/.zonai/rules/db_rules.exe';
  final exe = File(exePath);
  if (!exe.existsSync()) {
    stderr.writeln('Missing $exePath — compile rules first (zonai serve + r).');
    exitCode = 1;
    return;
  }

  final proc = await Process.start(
    exePath,
    const [],
    workingDirectory: playgroundRoot,
  );
  unawaited(proc.stderr.drain<void>());

  final lineIter = StreamIterator(
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );

  try {
    for (final ex in _exampleRequests()) {
      final body = jsonEncode(ex.toJson());
      proc.stdin.writeln(body);
      await proc.stdin.flush();

      final response = await _readCanAccessForId(lineIter, ex.id);
      if (response == null) {
        stderr.writeln('No can_access response for id ${ex.id}.');
        exitCode = 1;
        return;
      }
      stdout.writeln(
        '${ex.collection} ${ex.operation} -> canAccess: ${response.canAccess}',
      );
    }

    proc.stdin.writeln('kill');
    await proc.stdin.flush();
    await proc.stdin.close();

    final code = await proc.exitCode;
    if (code != 0) {
      stderr.writeln('db_rules.exe exited with $code');
      exitCode = code;
    }
  } finally {
    await lineIter.cancel();
  }
}

List<CollectionRulesRequest> _exampleRequests() {
  return [
    CollectionRulesRequest(
      collection: 'items',
      operation: 'view',
      isSuperUser: false,
    ),
    CollectionRulesRequest(
      collection: 'items',
      operation: 'view',
      isSuperUser: true,
    ),
  ];
}

Future<CollectionRulesResponse?> _readCanAccessForId(
  StreamIterator<String> lineIter,
  String wantId,
) async {
  while (await lineIter.moveNext()) {
    final parsed = _tryParseCanAccess(lineIter.current);
    if (parsed != null && parsed.id == wantId) {
      return parsed;
    }
  }
  return null;
}

CollectionRulesResponse? _tryParseCanAccess(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    final map = jsonDecode(trimmed) as Map<String, dynamic>;
    if (map['path'] == 'can_access' && map.containsKey('canAccess')) {
      return CollectionRulesResponse.fromJson(map);
    }
  } catch (_) {
    // Handler debug lines or non-JSON.
  }
  return null;
}
