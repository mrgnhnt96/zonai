import 'dart:convert';

import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db token list [options]

List every API token: what it is called, what it may reach, when it expires
and when it was last used. Never the token itself -- only its hash is
stored, and only its first characters are shown, enough to match a token in
a log line to the row it came from.

`last used` is what makes this list actionable. It is the answer to "is
anything still using this?", which is the question that has to be answerable
before anyone ever revokes anything.

Options:
  -h, --help              Show help information
      --all               Include revoked tokens
      --json              Print as JSON
''';

Future<int> listTokens() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final includeRevoked = args.getOrNull<bool>('all') == true;

  try {
    final tokens = await zonaiDB.listApiTokens(includeRevoked: includeRevoked);

    if (args.getOrNull<bool>('json') == true) {
      logger.info(
        const JsonEncoder.withIndent('  ').convert([
          for (final token in tokens)
            {
              'id': token.id.value,
              'name': token.name,
              'prefix': token.tokenPrefix,
              'scope': token.scopeJson,
              'boundTable': token.boundTable,
              'boundUserId': token.boundUserId,
              'createdAt': token.createdAt.toIso8601String(),
              'createdBy': token.createdBy,
              'expiresAt': token.expiresAt?.toIso8601String(),
              'revokedAt': token.revokedAt?.toIso8601String(),
              'lastUsedAt': token.lastUsedAt?.toIso8601String(),
            },
        ]),
      );
      return 0;
    }

    if (tokens.isEmpty) {
      logger.info(
        includeRevoked
            ? 'No API tokens'
            : 'No live API tokens (`--all` includes revoked ones)',
      );
      return 0;
    }

    logger.info('${tokens.length} API token(s):');
    for (final token in tokens) {
      final scope = token.scope;
      logger
        ..info('')
        ..info('  ${token.name}  (${token.id.value})')
        ..info('    token:      ${token.tokenPrefix}...')
        ..info('    tables:     ${(scope.tables.toList()..sort()).join(', ')}')
        ..info(
          '    operations: '
          '${([...scope.operations.map((o) => o.name), ...scope.customOperations]..sort()).join(', ')}',
        )
        ..info(
          '    admin:      ${scope.admin}${scope.canEdit ? ' (canEdit)' : ''}',
        )
        ..info('    created:    ${token.createdAt} by ${token.createdBy}')
        ..info('    expires:    ${token.expiresAt ?? 'never'}')
        ..info('    last used:  ${token.lastUsedAt ?? 'never'}');

      if (token.boundTable case final boundTable?) {
        logger.info('    acts as:    $boundTable/${token.boundUserId}');
      }
      if (token.revokedAt case final revokedAt?) {
        logger.info('    REVOKED:    $revokedAt');
      }
    }
    logger.info('');

    return 0;
  } catch (e, stack) {
    logger.error('Failed to list API tokens: $e', stack);
    return 1;
  }
}
