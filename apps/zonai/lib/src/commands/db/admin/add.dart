import 'dart:convert';

import 'package:zonai_schema/zonai_schema.dart' show AuthType;

import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';
import '../../../utils/admin_create_shape.dart';

const _usage = '''
Usage: zonai db admin add [options]

Create an admin account in the configured admin auth collection.
Admin sign-in requires an existing account; use this command to bootstrap
the first admin or add additional admins from the CLI.

`--password` is required only when the admin table supports password
sign-in. On an OAuth-only admin table, omit it -- the account signs in the
first time its email matches a verified provider identity.

Options:
  -h, --help              Show help information
  -e, --email=<address>   Admin email address (required)
  -p, --password=<value>  Admin password (required if the admin table
                           supports password sign-in; an error otherwise)
  -d, --data=<json>       JSON object of extra record fields (optional)
      --no-verify         Do not mark the account as verified
''';

Future<int> addAdmin() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final email = args.getOrNull<String>('email', abbr: 'e');
  if (email == null || email.isEmpty) {
    logger.error('Missing required option: --email');
    logger.info(_usage);
    return 1;
  }

  final password = args.getOrNull<String>('password', abbr: 'p');

  Map<String, dynamic>? object;
  if (args.getOrNull<String>('data', abbr: 'd') case final raw?) {
    object = _parseData(raw);
    if (object == null) {
      return 1;
    }
  }

  final verified = args.getOrNull<bool>('no-verify') != true;

  try {
    final (table, authTypes) = await zonaiDB.adminTable();
    final supportsPassword = authTypes.contains(AuthType.password);

    if (supportsPassword && (password == null || password.isEmpty)) {
      logger.error(
        'Missing required option: --password (admin table "$table" '
        'supports password sign-in)',
      );
      logger.info(_usage);
      return 1;
    }

    if (!supportsPassword && password != null) {
      logger.error(
        'Admin table "$table" has no password sign-in configured; omit '
        '--password -- this account signs in through its other configured '
        'auth type instead',
      );
      logger.info(_usage);
      return 1;
    }

    final tableShape = await resolveAdminTableShape(zonaiDB);
    final extraFields = adminExtraCreateFields(tableShape.columns);
    final resolvedObject = resolveAdminCreateObject(
      extraFields: extraFields,
      data: object,
    );

    final user = await zonaiDB.createAdmin(
      email: email,
      password: password,
      object: resolvedObject.isEmpty ? null : resolvedObject,
      verified: verified,
    );

    logger.info('Admin created successfully');
    logger.info('  id: ${user['id']}');
    logger.info('  email: ${user['email'] ?? email}');
    for (final entry in user.entries) {
      if (entry.key == 'id' ||
          entry.key == 'email' ||
          entry.key == 'password') {
        continue;
      }
      logger.info('  ${entry.key}: ${entry.value}');
    }
    if (verified) {
      logger.info('  verified: true');
    }

    return 0;
  } catch (e, stack) {
    logger.error('Failed to create admin: $e', stack);
    return 1;
  }
}

Map<String, dynamic>? _parseData(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      logger.error('--data must be a JSON object, got ${decoded.runtimeType}');
      logger.info(_usage);
      return null;
    }

    return decoded.map((key, value) => MapEntry('$key', value));
  } on FormatException catch (e) {
    logger.error('Invalid JSON for --data: $e');
    logger.info(_usage);
    return null;
  }
}
