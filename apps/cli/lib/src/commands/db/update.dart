import 'dart:convert';

import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/zonai_db.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';

const _usage = '''
Usage: zonai db update <collection> [options]

Options:
  -h, --help      Show help information
  -d, --data      Data to update
  -o, --operation Operation to perform
''';

Future<int> update(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  if (path.isEmpty || path.length != 1) {
    logger.err('Expected 1 argument: <collection>');
    logger.info(_usage);
    return 1;
  }

  final collection = path.single;
  if (collection.isEmpty) {
    logger.err('Collection cannot be empty');
    logger.info(_usage);
    return 1;
  }

  final operation = args.getOrNull<String>(
    'operation',
    aliases: ['op'],
    abbr: 'o',
  );

  if (operation == null || operation.isEmpty) {
    logger.err('--operation is required to update a record');
    logger.info(_usage);
    return 1;
  }
  final collectionOperation = CollectionOperation.fromString(operation);
  if (collectionOperation == null) {
    logger.err('Invalid operation: $operation');
    logger.info(_usage);
    return 1;
  }

  Map<String, dynamic>? json;

  final data = args.getOrNull<String>('data');
  if (data case null when collectionOperation.requireObject) {
    logger.err('--data is required to update a record');
    logger.info(_usage);
    return 1;
  }
  if (data case final data? when data.isNotEmpty) {
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (e) {
      logger.err('Invalid JSON: $data');
      logger.info(_usage);
      return 1;
    }
  }

  if (json?.isEmpty case true || null when collectionOperation.requireObject) {
    logger.err('Data cannot be empty');
    logger.info(_usage);
    return 1;
  }

  switch (collectionOperation) {
    case .create:
      await zonaiDB.create(collection, json ?? {});
    case .update:
      await zonaiDB.update(collection, json ?? {});
    case .delete:
      await zonaiDB.delete(collection, json ?? {});
    case .view:
      await zonaiDB.view(collection, json ?? {});
    case .list:
      await zonaiDB.list(collection, json ?? {});
    case .search:
      await zonaiDB.search(collection, json ?? {});
  }

  return 0;
}
