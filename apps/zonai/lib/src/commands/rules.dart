import 'package:nocterm/src/utils/unicode_width.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/types/jwt.dart';

import '../deps/args.dart';
import '../deps/logger.dart';
import '../messengers/rules_mailman.dart';
import '../utils/jwt_generator.dart';

const _actionColumnWidth = 6;

const _usage = '''
Usage: zonai rules <subcommand> [options]

Subcommands:
  list                      List collection actions for all tables
  table <name> <operation>  Show table access rules (e.g. read, create)

Options:
  -h, --help              Show help information
      --jwt=<token>       JWT bearer token to evaluate rules as that user
                          (omit to evaluate as an anonymous request)
  -c, --config=<path>     Path to zonai.yml

The rules worker must already be compiled (`zonai compile`); the server does
not need to be running.
''';

Future<int> rules(List<String> path) async {
  // Not `&& path.isEmpty`: `rules list --help` and `rules table t read --help`
  // used to spawn the rules worker and evaluate, ignoring the flag entirely.
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final mailman = RulesMailman();
  try {
    final jwt = await _resolveJwt();
    switch (path) {
      case ['list' || 'ls']:
        return await _listActions(mailman, jwt: jwt);
      case ['table', final String table, final String operation]:
        return await _showTableRules(mailman, table, operation, jwt: jwt);
      default:
        logger.info(_usage);
        return 1;
    }
  } catch (e, stack) {
    logger.error('Failed to fetch rules: $e', e, stack);
    return 1;
  } finally {
    await mailman.kill(failPending: false);
  }
}

Future<Jwt?> _resolveJwt() async {
  final token = args.getOrNull<String>('jwt');
  if (token == null) return null;
  return await parseJwtTokenClaimsOnly(token);
}

void _logJwtContext(Jwt? jwt) {
  if (jwt case final jwt?) {
    final admin = switch (jwt.admin) {
      (isAdmin: true, canEdit: true) => 'admin (can edit)',
      (isAdmin: true, canEdit: false) => 'admin (read-only)',
      (isAdmin: true, canEdit: null) => 'admin',
      (isAdmin: false, canEdit: _) => 'user',
    };
    logger.info(
      'Evaluating as $admin: userId=${jwt.userId.value} table=${jwt.table}',
    );
    return;
  }

  logger.info('Evaluating as anonymous (no JWT)');
}

Future<int> _listActions(RulesMailman mailman, {Jwt? jwt}) async {
  _logJwtContext(jwt);

  final response = await mailman.send<AllTableCollectionActionsResponse>(
    GetAllTableCollectionActionsRequest(jwt: jwt),
  );

  if (response.actions.isEmpty) {
    logger.info('No table collection actions found.');
    return 0;
  }

  final entries = response.actions.entries.toList()
    ..sort((a, b) => _compareTableNames(a.key, b.key));

  final nameWidth = entries
      .map((entry) => entry.key.length)
      .fold('TABLE'.length, (width, length) => width > length ? width : length);

  logger.info(
    '${_padDisplayRight('TABLE', nameWidth)}  '
    '${_padDisplayCenter('LIST', _actionColumnWidth)} '
    '${_padDisplayCenter('VIEW', _actionColumnWidth)} '
    '${_padDisplayCenter('CREATE', _actionColumnWidth)} '
    '${_padDisplayCenter('UPDATE', _actionColumnWidth)} '
    '${_padDisplayCenter('DELETE', _actionColumnWidth)}',
  );

  for (final entry in entries) {
    final actions = entry.value;
    logger.info(
      '${_padDisplayRight(entry.key, nameWidth)}  '
      '${_padDisplayCenter(_formatAction(actions.canList), _actionColumnWidth)} '
      '${_padDisplayCenter(_formatAction(actions.canView), _actionColumnWidth)} '
      '${_padDisplayCenter(_formatAction(actions.canCreate), _actionColumnWidth)} '
      '${_padDisplayCenter(_formatAction(actions.canUpdate), _actionColumnWidth)} '
      '${_padDisplayCenter(_formatAction(actions.canDelete), _actionColumnWidth)}',
    );
  }

  return 0;
}

String _formatAction(bool allowed) => allowed ? '✅' : '❌';

String _padDisplayCenter(String text, int width) {
  final padding = width - UnicodeWidth.stringWidth(text);
  if (padding <= 0) return text;
  final left = padding ~/ 2;
  final right = padding - left;
  return '${' ' * left}$text${' ' * right}';
}

String _padDisplayRight(String text, int width) {
  final padding = width - UnicodeWidth.stringWidth(text);
  return padding <= 0 ? text : '$text${' ' * padding}';
}

int _compareTableNames(String a, String b) {
  final aSystem = a.startsWith('_');
  final bSystem = b.startsWith('_');
  if (aSystem != bSystem) return aSystem ? 1 : -1;
  return a.compareTo(b);
}

Future<int> _showTableRules(
  RulesMailman mailman,
  String table,
  String operation, {
  Jwt? jwt,
}) async {
  _logJwtContext(jwt);

  final response = await mailman.send<TableRulesResponse?>(
    TableRulesRequest(table: table, operation: operation, jwt: jwt),
  );

  if (response == null) {
    logger.info('No rules found for $table ($operation)');
    return 0;
  }

  logger.info(
    '$table.$operation: canAccess=${response.canAccess} id=${response.id}',
  );
  return 0;
}
