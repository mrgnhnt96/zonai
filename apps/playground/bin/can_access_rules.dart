import 'dart:convert';
import 'dart:io';

import 'package:zonai_schema/src/handlers/rules/rule_responses.dart';

/// Talks to `.zonai/rules/db_rules.exe` with a `can_access` request so you can
/// verify table access against [Rules] (playground `ItemRules`: super-user only).
///
/// Run from `apps/playground`:
/// `dart run bin/can_access_rules.dart`
///
/// One process per request, single JSON line then close stdin — otherwise stdin
/// and `kill` may arrive in one chunk and [MessageHandler] cannot decode it.
Future<void> main() async {
  final playgroundRoot =
      File(Platform.script.toFilePath()).parent.parent.path;
  final exePath = '$playgroundRoot/.zonai/rules/db_rules.exe';
  final exe = File(exePath);
  if (!exe.existsSync()) {
    stderr.writeln('Missing $exePath — compile rules first (zonai serve + r).');
    exitCode = 1;
    return;
  }

  final regular = await _queryCanAccess(
    exePath: exePath,
    workingDirectory: playgroundRoot,
    id: 'demo-regular',
    collection: 'items',
    operation: 'view',
    isSuperUser: false,
  );
  final superUser = await _queryCanAccess(
    exePath: exePath,
    workingDirectory: playgroundRoot,
    id: 'demo-super',
    collection: 'items',
    operation: 'view',
    isSuperUser: true,
  );

  if (regular == null || superUser == null) {
    stderr.writeln('Failed to parse can_access response(s).');
    exitCode = 1;
    return;
  }

  stdout.writeln('Regular user view/items -> canAccess: ${regular.canAccess}');
  stdout.writeln('Super user  view/items -> canAccess: ${superUser.canAccess}');
}

Future<CanAccessResponse?> _queryCanAccess({
  required String exePath,
  required String workingDirectory,
  required String id,
  required String collection,
  required String operation,
  required bool isSuperUser,
}) async {
  final body = jsonEncode({
    'path': 'can_access',
    'id': id,
    'collection': collection,
    'operation': operation,
    'isSuperUser': isSuperUser,
  });
  final proc = await Process.start(
    exePath,
    const [],
    workingDirectory: workingDirectory,
  );
  proc.stdin.writeln(body);
  await proc.stdin.close();
  final out = await proc.stdout.transform(utf8.decoder).join();
  final err = await proc.stderr.transform(utf8.decoder).join();
  final code = await proc.exitCode;
  if (code != 0) {
    stderr.writeln('db_rules.exe failed ($code): $err');
    return null;
  }
  return _firstCanAccessLine(out);
}

CanAccessResponse? _firstCanAccessLine(String blob) {
  for (final line in const LineSplitter().convert(blob)) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('{')) continue;
    try {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      if (map['path'] == 'can_access' && map.containsKey('canAccess')) {
        return CanAccessResponse.fromJson(map);
      }
    } catch (_) {
      // Handler debug lines mixed into stdout.
    }
  }
  return null;
}
