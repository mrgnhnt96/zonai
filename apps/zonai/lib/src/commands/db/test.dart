import 'dart:async';

import 'package:zonai_schema/src/update/update.dart';

import '../../db_mutator/payloads/payloads.dart';
import '../../deps/logger.dart';
import '../../deps/zonai_db.dart';

Future<void> main() async {
  await test();
}

Future<int> test() async {
  logger.info('CREATING USER');
  if (await _createUser() case final int exitCode) {
    return exitCode;
  }

  logger.info('--------------------------------');
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

  logger.info('STREAM LIST');
  if (await _streamList(id: id!) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('STREAM ONE');
  if (await _streamOne(id: id) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('UPDATING RECORD');
  if (await _update(id: id) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('VIEWING RECORD');
  if (await _view(id: id) case final int exitCode) {
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

Future<int?> _createUser() async {
  final (error, result) = await zonaiDB.create(
    'users',
    .new(
      object: {
        'email': 'test@test.com',
        'password': 'test',
        'name': 'Test User',
      },
    ),
  );

  if (error != null || result == null) {
    logger.err(
      'Failed to create user: ${error ?? 'no error (missing result map)'}',
    );
    return 1;
  }
  return null;
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
    .new(where: NotNull('id')),
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

Future<int?> _streamList({required String id}) async {
  // Resqlite drops intermediate reactive results when a stream is invalidated
  // again while its re-query is still in-flight, so two back-to-back updates
  // may yield a single emission (the final snapshot).
  const expectedBody = 'Test body updated (2)';

  final stream = zonaiDB.streamList('items', .new(where: Eq('id', id)));

  final completer = Completer<void>();
  final listener = stream.listen((result) {
    logger.info('Stream result: ${result}');

    final row = result.isEmpty ? null : result.single;
    if (row?['body'] == expectedBody && !completer.isCompleted) {
      completer.complete();
    }
  });

  await zonaiDB.update(
    'items',
    .new(
      where: Eq('id', id),
      updates: [
        ObjectUpdate({'body': 'Test body updated (1)'}),
      ],
    ),
  );

  await zonaiDB.update(
    'items',
    .new(
      where: Eq('id', id),
      updates: [
        ObjectUpdate({'body': 'Test body updated (2)'}),
      ],
    ),
  );

  await completer.future;
  listener.cancel().ignore();
  return null;
}

Future<int?> _streamOne({required String id}) async {
  const step1Body = 'Stream-one probe (a)';
  const step2Body = 'Stream-one probe (b)';

  final stream = zonaiDB.streamOne('items', .new(where: Eq('id', id)));

  final completer = Completer<void>();
  final listener = stream.listen((result) {
    logger.info('Stream result: ${result}');

    if (result['body'] == step2Body && !completer.isCompleted) {
      completer.complete();
    }
  });

  await zonaiDB.update(
    'items',
    .new(
      where: Eq('id', id),
      updates: [
        ObjectUpdate({'body': step1Body}),
      ],
    ),
  );

  await zonaiDB.update(
    'items',
    .new(
      where: Eq('id', id),
      updates: [
        ObjectUpdate({'body': step2Body}),
      ],
    ),
  );

  await completer.future;
  listener.cancel().ignore();
  return null;
}

Future<int?> _delete({required String id}) async {
  final (error, result) = await zonaiDB.delete(
    'items',
    .new(where: Eq('id', id)),
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
    .new(where: Eq('id', id)),
  );
  if (error != null || result == null) {
    logger.err('Failed to view records: $error');
    return 1;
  }

  logger.info('Viewed ${result}');
  return null;
}

Future<int?> _update({required String id}) async {
  final (error, result) = await zonaiDB.update(
    'items',
    .new(
      where: Eq('id', id),
      updates: [
        ObjectUpdate({'body': 'Test body updated'}),
      ],
    ),
  );
  if (error != null || result == null) {
    logger.err('Failed to update records: $error');
    return 1;
  }
  return null;
}

String _generateId() {
  return 'test-${DateTime.now().millisecondsSinceEpoch}_it';
}
