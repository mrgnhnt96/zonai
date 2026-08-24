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
                               delete. Or "*" for every one, including
                               operations added in a later zonai -- the "*"
                               is stored, not expanded. Or use --read /
                               --write.
      --read                  Shorthand for --operations=view,list,count
      --write                 Shorthand for --operations=create,update,delete
      --custom=<a,b>          Named custom operations, or "*"
      --no-admin              Mint a token that is NOT an admin. Tokens are
                               admin by default, because the DEFAULT rules
                               deny everyone but an admin -- so a non-admin
                               token is inert against any collection whose
                               rules were never overridden. What the token
                               may reach is --tables and --operations; admin
                               is what lets it reach them at all.
      --can-edit,             The write half of admin. Derived when unstated:
      --no-can-edit            on by default for an admin token granted
                               create/update/delete, off for a read-only one.
                               --can-edit requires admin.
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
  var allOperations = false;
  if (_stringOption('operations', abbr: 'o') case final raw?) {
    for (final name in _splitList(raw)) {
      if (name == ApiTokenScope.wildcard) {
        allOperations = true;
        continue;
      }
      final operation = TableOperation.fromString(name);
      if (operation == null) {
        logger.error(
          'Unknown operation "$name" -- expected one of: '
          '${TableOperation.values.map((o) => o.name).join(', ')}, '
          'or "${ApiTokenScope.wildcard}" for all of them',
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

  if (operations.isEmpty && !allOperations && customOperations.isEmpty) {
    logger.error(
      'Missing required option: --operations (or --read / --write). A token '
      'that may reach a table but perform nothing on it can do nothing.',
    );
    logger.info(_usage);
    return 1;
  }

  // Admin unless refused: see `ApiTokenScope.admin`. `--no-admin` parses to
  // `false`; an absent flag reads back as null.
  final admin = args.getOrNull<bool>('admin') != false;
  // Left null when neither flag was passed, so the scope derives it from the
  // granted operations rather than being pinned to a hard false.
  final canEdit = args.getOrNull<bool>('can-edit', aliases: ['canEdit']);
  if (canEdit == true && !admin) {
    logger.error(
      '--can-edit is the write half of admin, and --no-admin was passed. '
      'Drop one of them.',
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
        allOperations: allOperations,
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
        '${[if (allOperations) ApiTokenScope.wildcard else ...operations.map((o) => o.name), ...customOperations].join(', ')}',
      )
      ..info(
        '  admin:      '
        '${minted.row.scope.admin ? 'yes' : 'no'}'
        '${minted.row.scope.canEdit ? ', can edit' : ''}',
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
      // --no-admin was asked for, so this is not a surprise -- but the
      // consequence lands nowhere near where they will look for it, and a
      // token that is denied everything reads as a broken token.
      logger
        ..info('')
        ..info(
          '  Note: --no-admin, so this token is denied by the DEFAULT rules, '
          'which allow',
        )
        ..info(
          '  only admins. Override the collection\'s rules to admit it (for '
          'example on',
        )
        ..info('  jwt.claims), or re-mint without --no-admin.');
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
