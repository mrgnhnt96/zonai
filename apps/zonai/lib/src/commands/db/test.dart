import 'dart:async';

import 'package:zonai_schema/src/update/update.dart';

import '../../db_mutator/payloads/payloads.dart';
import '../../deps/logger.dart';
import '../../deps/zonai_db.dart';

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
  final stream = zonaiDB.streamList('items', .new(where: Eq('id', id)));

  final completer = Completer<void>();
  var count = 0;
  final listener = stream.listen((result) {
    logger.info('Stream result: ${result}');

    // Two updates below → two stream emissions (initial read is not yielded).
    if (++count == 2 && !completer.isCompleted) {
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
  final stream = zonaiDB.streamOne('items', .new(where: Eq('id', id)));

  final completer = Completer<void>();
  var count = 0;
  final listener = stream.listen((result) {
    logger.info('Stream result: ${result}');

    if (++count == 2 && !completer.isCompleted) {
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
