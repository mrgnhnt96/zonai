import 'dart:convert';

import 'package:zonai_schema/src/handlers/rules/rule_request.dart'
    show TableOperation;
import 'package:zonai_schema/zonai_schema.dart' show ApiTokenScope;

import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db token create [options]

Mint an API token. The token is printed ONCE and cannot be recovered
afterwards -- only its SHA-256 is stored. Copy it before you close the
terminal.

Needs no running server, no session and no JWT signing secret: write access
to the database file is the authorization.

Options:
  -h, --help                  Show help information
  -n, --name=<label>          What this token is for (required).
                               "nightly-backup", "vercel-preview".
  -t, --tables=<a,b>          Collections it may reach, or "*" for every app
                               collection (required). Quote the "*" so your
                               shell does not expand it.
  -o, --operations=<a,b>      Any of: view, list, count, create, update,
                               delete. Or use --read / --write.
      --read                  Shorthand for --operations=view,list,count
      --write                 Shorthand for --operations=create,update,delete
      --custom=<a,b>          Named custom operations, or "*"
      --admin                 Let the token satisfy the DEFAULT rules, which
                               deny everyone but an admin. Without this a
                               token is inert against any collection whose
                               rules were never overridden.
      --can-edit              The write half of --admin. Requires --admin.
      --expires=<90d|12h|30m> When it stops working
      --no-expires            Never expires (the default)
      --claims=<json>         JSON object merged into jwt.claims, so rules
                               already reading jwt.claims['role'] work
      --as=<table>/<id>       Act as one auth row, so ownership rules match.
                               Omit for a standalone service identity that
                               owns no rows.
      --json                  Print the result as JSON

An API token can never reach zonai's internal tables (`_jwt`,
`_api_tokens`, ...), under "*" or named explicitly.
''';

Future<int> createToken() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final name = args.getOrNull<String>('name', abbr: 'n');
  if (name == null || name.trim().isEmpty) {
    logger.error('Missing required option: --name');
    logger.info(_usage);
    return 1;
  }

  final rawTables = _stringOption('tables', abbr: 't');
  if (rawTables == null || rawTables.trim().isEmpty) {
    logger.error('Missing required option: --tables');
    logger.info(_usage);
    return 1;
  }
  final tables = _splitList(rawTables);

  final operations = <TableOperation>{};
  if (args.getOrNull<bool>('read') == true) {
    operations.addAll(const [
      TableOperation.view,
      TableOperation.list,
      TableOperation.count,
    ]);
  }
  if (args.getOrNull<bool>('write') == true) {
    operations.addAll(const [
      TableOperation.create,
      TableOperation.update,
      TableOperation.delete,
    ]);
  }
  if (_stringOption('operations', abbr: 'o') case final raw?) {
    for (final name in _splitList(raw)) {
      final operation = TableOperation.fromString(name);
      if (operation == null) {
        logger.error(
          'Unknown operation "$name" -- expected one of: '
          '${TableOperation.values.map((o) => o.name).join(', ')}',
        );
        return 1;
      }
      operations.add(operation);
    }
  }

  final customOperations = switch (_stringOption('custom')) {
    final raw? => _splitList(raw),
    null => <String>{},
  };

  if (operations.isEmpty && customOperations.isEmpty) {
    logger.error(
      'Missing required option: --operations (or --read / --write). A token '
      'that may reach a table but perform nothing on it can do nothing.',
    );
    logger.info(_usage);
    return 1;
  }

  final admin = args.getOrNull<bool>('admin') == true;
  final canEdit =
      args.getOrNull<bool>('can-edit', aliases: ['canEdit']) == true;
  if (canEdit && !admin) {
    logger.error(
      '--can-edit is the write half of --admin. Pass --admin as well, or '
      'neither.',
    );
    return 1;
  }

  DateTime? expiresAt;
  if (_stringOption('expires') case final raw? when raw != 'false') {
    final duration = _parseDuration(raw);
    if (duration == null) {
      logger.error(
        'Could not read --expires="$raw". Use a count and a unit: 90d, 12h, '
        '30m.',
      );
      return 1;
    }
    expiresAt = DateTime.now().add(duration);
  }

  Map<String, dynamic> claims = const {};
  if (_stringOption('claims') case final raw?) {
    try {
      claims = jsonDecode(raw) as Map<String, dynamic>;
    } on Object catch (e) {
      logger.error('--claims must be a JSON object: $e');
      return 1;
    }
  }

  String? boundTable;
  String? boundUserId;
  if (_stringOption('as') case final raw?) {
    final parts = raw.split('/');
    if (parts.length != 2 || parts.any((p) => p.trim().isEmpty)) {
      logger.error(
        '--as must look like <table>/<row-id>, for example '
        'users/abc123_usr',
      );
      return 1;
    }
    boundTable = parts.first.trim();
    boundUserId = parts.last.trim();
  }

  try {
    final minted = await zonaiDB.createApiToken(
      name: name,
      scope: ApiTokenScope(
        tables: tables,
        operations: operations,
        customOperations: customOperations,
        admin: admin,
        canEdit: canEdit,
      ),
      createdBy: '__cli__',
      claims: claims,
      boundTable: boundTable,
      boundUserId: boundUserId,
      expiresAt: expiresAt,
    );

    if (args.getOrNull<bool>('json') == true) {
      logger.info(
        const JsonEncoder.withIndent('  ').convert({
          'id': minted.row.id.value,
          'name': minted.row.name,
          'token': minted.secret,
          'scope': minted.row.scopeJson,
          'expiresAt': minted.row.expiresAt?.toIso8601String(),
        }),
      );
      return 0;
    }

    logger
      ..info('')
      ..info('  ${minted.secret}')
      ..info('')
      ..info(
        '  This is the only time it will be shown. The server keeps only its '
        'hash.',
      )
      ..info('')
      ..info('  id:         ${minted.row.id.value}')
      ..info('  name:       ${minted.row.name}')
      ..info('  tables:     ${tables.join(', ')}')
      ..info(
        '  operations: '
        '${[...operations.map((o) => o.name), ...customOperations].join(', ')}',
      )
      ..info(
        '  expires:    '
        '${minted.row.expiresAt?.toIso8601String() ?? 'never -- revoke with '
                '`zonai db token revoke ${minted.row.id.value}`'}',
      );

    if (boundTable != null) {
      logger.info('  acts as:    $boundTable/$boundUserId');
    }

    if (!admin) {
      // The first token someone mints usually looks broken without this, and
      // the reason is nowhere near where they will look for it.
      logger
        ..info('')
        ..info(
          '  Note: this token is not an admin token, so it is denied by the '
          'DEFAULT rules,',
        )
        ..info(
          '  which allow only admins. Either override the collection\'s rules '
          'to admit it',
        )
        ..info('  (for example on jwt.claims), or re-mint with --admin.');
    }

    logger.info('');
    return 0;
  } catch (e, stack) {
    logger.error('Failed to create API token: $e', stack);
    return 1;
  }
}

/// [Args] coerces a numeric-looking value to `int`/`double`, so an option that
/// is semantically a string has to be read back as one.
String? _stringOption(String key, {String? abbr}) {
  final value = args.getOrNull<Object>(key, abbr: abbr);
  return switch (value) {
    null => null,
    final bool _ => null,
    final value => '$value',
  };
}

Set<String> _splitList(String raw) => {
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
};

/// `90d`, `12h`, `30m`, `45s`, or a bare number of days.
Duration? _parseDuration(String raw) {
  final match = RegExp(r'^(\d+)\s*([smhdw]?)$').firstMatch(raw.trim());
  if (match == null) return null;

  final count = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    's' => Duration(seconds: count),
    'm' => Duration(minutes: count),
    'h' => Duration(hours: count),
    'w' => Duration(days: count * 7),
    _ => Duration(days: count),
  };
}
