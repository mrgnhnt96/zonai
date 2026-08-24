import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _revokeUsage = '''
Usage: zonai db token revoke <id>

Stop a token working. It fails on the very next request: resolution reads
the row every time, so there is no cache to wait out, no restart and no
redeploy.

The row stays, stamped with the time, so "who had access and until when" is
still answerable. `zonai db token delete` is the version that removes it.

<id> may be a unique prefix of the id `zonai db token list` prints. An
ambiguous prefix is refused rather than guessed -- picking the first match
for a revoke is how the wrong integration goes down.

Options:
  -h, --help              Show help information
''';

const _deleteUsage = '''
Usage: zonai db token delete <id>

Remove a token's row entirely. It stops working, and the record of it having
existed goes too -- prefer `zonai db token revoke` unless the row itself is
the thing to be rid of.

<id> may be a unique prefix.

Options:
  -h, --help              Show help information
''';

Future<int> revokeToken(String? positional) async {
  if (args.help) {
    logger.info(_revokeUsage);
    return 1;
  }

  final id = _id(positional);
  if (id == null) {
    logger.error('Missing token id');
    logger.info(_revokeUsage);
    return 1;
  }

  try {
    final token = await zonaiDB.revokeApiToken(id: id);
    logger.info(
      'Revoked "${token.name}" (${token.id.value}) at ${token.revokedAt}',
    );
    return 0;
  } catch (e, stack) {
    logger.error('Failed to revoke API token: $e', stack);
    return 1;
  }
}

Future<int> deleteToken(String? positional) async {
  if (args.help) {
    logger.info(_deleteUsage);
    return 1;
  }

  final id = _id(positional);
  if (id == null) {
    logger.error('Missing token id');
    logger.info(_deleteUsage);
    return 1;
  }

  try {
    await zonaiDB.deleteApiToken(id: id);
    logger.info('Deleted API token "$id"');
    return 0;
  } catch (e, stack) {
    logger.error('Failed to delete API token: $e', stack);
    return 1;
  }
}

/// The id as a positional (`zonai db token revoke abc123`) or as `--id`.
String? _id(String? positional) {
  if (positional case final id? when id.trim().isNotEmpty) {
    return id.trim();
  }
  if (args.rest.firstOrNull case final id? when id.trim().isNotEmpty) {
    return id.trim();
  }
  return switch (args.getOrNull<Object>('id')) {
    null => null,
    final bool _ => null,
    final value => '$value',
  };
}
