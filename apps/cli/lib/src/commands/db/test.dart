import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/zonai_db.dart';

Future<void> main() async {
  await test();
}

Future<int> test() async {
  logger.info('CREATING RECORD');
  if (await _create() case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('LISTING RECORDS');
  final (exitCode, id) = await _list();
  if (exitCode != null) {
    return exitCode;
  }
  logger.info('ID: $id');
  logger.info('--------------------------------');

  logger.info('VIEWING RECORD');
  if (await _view(id: id!) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('DELETING RECORD');
  if (await _delete(id: id) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  return 0;
}

Future<int?> _create() async {
  final (error, result) = await zonaiDB.create(
    'items',
    .new(object: {'body': 'Test body', 'id': _generateId()}),
  );
  if (error != null || result == null) {
    logger.err('Failed to create record: $error');
    return 1;
  }

  logger.info('Created record: ${result}');
  return null;
}

Future<(int?, String?)> _list() async {
  final (error, result) = await zonaiDB.list(
    'items',
    .new(where: Where('"items"."id" IS NOT NULL')),
  );
  if (error != null || result == null) {
    logger.err('Failed to list records: $error');
    return (1, null);
  }

  logger.info('Found ${result.length} records');
  for (final record in result) {
    logger.info('Record: ${record}');
  }
  return (null, result.last['id'] as String?);
}

Future<int?> _delete({required String id}) async {
  final (error, result) = await zonaiDB.delete(
    'items',
    .new(where: Where('"items"."id" = "$id"')),
  );

  if (error != null || result == null) {
    logger.err('Failed to delete records: $error');
    return 1;
  }

  logger.info('Deleted ${result} records');
  return null;
}

Future<int?> _view({required String id}) async {
  final (error, result) = await zonaiDB.view(
    'items',
    .new(where: Where('"items"."id" = "$id"')),
  );
  if (error != null || result == null) {
    logger.err('Failed to view records: $error');
    return 1;
  }

  logger.info('Viewed ${result}');
  return null;
}

String _generateId() {
  return 'test-${DateTime.now().millisecondsSinceEpoch}_it';
}
