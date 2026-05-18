import 'dart:async';
import 'dart:math';

import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../../db_mutator/payloads/payloads.dart';
import '../../deps/logger.dart';
import '../../deps/zonai_db.dart';

Future<int> test() async {
  logger.info('AUTHENTICATE');
  if (await _authenticate() case final int exitCode) {
    return exitCode;
  }

  String email;
  {
    logger.info('--------------------------------');
    logger.info('SIGN UP');
    final (exitCode, userEmail) = await _signUp();
    if (exitCode != null || userEmail == null) {
      return exitCode ?? 1;
    }

    email = userEmail;
  }

  String jwt;

  {
    logger.info('--------------------------------');
    logger.info('SIGN IN');
    final (exitCode, signedInJwt) = await _signIn(email);
    if (exitCode != null || signedInJwt == null) {
      return exitCode ?? 1;
    }

    jwt = signedInJwt;
  }

  logger.info('--------------------------------');
  logger.info('CREATING USER');
  if (await _createUser() case final int exitCode) {
    return exitCode;
  }

  logger.info('--------------------------------');
  logger.info('CREATING RECORD');
  if (await _create(jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('LISTING RECORDS');
  final (exitCode, id) = await _list(jwt: jwt);
  if (exitCode != null) {
    return exitCode;
  }
  logger.info('ID: $id');
  logger.info('--------------------------------');

  {
    logger.info('COUNTING RECORDS');
    final (exitCode, count) = await _count(jwt: jwt);
    if (exitCode != null) {
      return exitCode;
    }
    logger.info('Count: $count');
    logger.info('--------------------------------');
  }
  logger.info('STREAM LIST');
  if (await _streamList(id: id!, jwt: jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('STREAM ONE');
  if (await _streamOne(id: id, jwt: jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('UPDATING RECORD');
  if (await _update(id: id, jwt: jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('VIEWING RECORD');
  if (await _view(id: id, jwt: jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('DELETING RECORD');
  if (await _delete(id: id, jwt: jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

  logger.info('LOGOUT');
  if (await _logout(jwt: jwt) case final int exitCode) {
    return exitCode;
  }

  logger.info('--------------------------------');

  return 0;
}

Future<int?> _logout({required String jwt}) async {
  await zonaiDB.logout(jwt);

  return null;
}

Future<(int?, String?)> _signUp() async {
  final random = Random();
  final nonce = random.nextInt(1000000);
  final uniqueTimestamp = DateTime.now().millisecondsSinceEpoch + nonce;

  final email = 'test+$uniqueTimestamp@test.com';

  final result = await zonaiDB.signUp(
    'users',
    SignUpPasswordAuthPayload(
      email: email,
      password: 'test',
      object: {'name': 'Test User'},
    ),
  );

  logger.info('Signed up user: ${result.user['Id']}');

  return (null, email);
}

Future<(int?, String?)> _signIn(String email) async {
  final result = await zonaiDB.signIn(
    'users',
    SignInPasswordAuthPayload(email: email, password: 'test'),
  );

  logger.info('Signed in user: ${result.user['id']}');

  return (null, result.jwt);
}

Future<int?> _authenticate() async {
  final random = Random();
  final nonce = random.nextInt(1000000);
  final uniqueTimestamp = DateTime.now().millisecondsSinceEpoch + nonce;

  final result = await zonaiDB.authenticate(
    'users',
    PasswordAuthPayload(
      email: 'test+$uniqueTimestamp@test.com',
      password: 'test',
      object: {'name': 'Test User'},
    ),
  );

  logger.info('Authenticated user: ${result.user['id']}');

  return null;
}

Future<int?> _createUser() async {
  try {
    final result = await zonaiDB.create(
      'users',
      .new(
        object: {
          'email': 'test@test.com',
          'password': 'test',
          'name': 'Test User',
        },
      ),
    );

    logger.info('Should not be able to create user: ${result}');
    return 1;
  } catch (e) {
    // expected
    return null;
  }
}

Future<int?> _create(String jwt) async {
  final result = await zonaiDB.create(
    'items',
    .new(jwt: jwt, object: {'body': 'Test body', 'id': _generateId()}),
  );

  logger.info('Created record: ${result}');
  return null;
}

Future<(int?, String?)> _list({required String jwt}) async {
  final result = await zonaiDB.list(
    'items',
    .new(jwt: jwt, where: NotNull('id')),
  );

  logger.info('Found ${result.length} records');
  for (final record in result) {
    logger.info('Record: ${record}');
  }
  return (null, result.last['id'] as String?);
}

Future<(int?, int?)> _count({required String jwt}) async {
  final result = await zonaiDB.count(
    'items',
    .new(jwt: jwt, where: NotNull('id')),
  );

  logger.info('Found ${result} records');
  return (null, result);
}

Future<int?> _streamList({required String id, required String jwt}) async {
  // Resqlite drops intermediate reactive results when a stream is invalidated
  // again while its re-query is still in-flight, so two back-to-back updates
  // may yield a single emission (the final snapshot).
  const expectedBody = 'Test body updated (2)';

  final stream = zonaiDB.streamList(
    'items',
    .new(jwt: jwt, where: Eq('id', id)),
  );

  final completer = Completer<void>();
  final listener =
      stream.listen((result) {
        logger.info('Stream result: ${result}');

        final row = result.isEmpty ? null : result.single;
        if (row?['body'] == expectedBody && !completer.isCompleted) {
          completer.complete();
        }
      })..onError((e, stack) {
        logger.error('Stream error', e, stack);
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

Future<int?> _streamOne({required String id, required String jwt}) async {
  const step1Body = 'Stream-one probe (a)';
  const step2Body = 'Stream-one probe (b)';

  final stream = zonaiDB.streamOne(
    'items',
    .new(jwt: jwt, where: Eq('id', id)),
  );

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

Future<int?> _delete({required String id, required String jwt}) async {
  final result = await zonaiDB.delete(
    'items',
    .new(jwt: jwt, where: Eq('id', id)),
  );

  logger.info('Deleted ${result} records');
  return null;
}

Future<int?> _view({required String id, required String jwt}) async {
  final result = await zonaiDB.read(
    'items',
    .new(jwt: jwt, where: Eq('id', id)),
  );

  logger.info('Viewed ${result}');
  return null;
}

Future<int?> _update({required String id, required String jwt}) async {
  final result = await zonaiDB.update(
    'items',
    .new(
      jwt: jwt,
      where: Eq('id', id),
      updates: [
        ObjectUpdate({'body': 'Test body updated'}),
      ],
    ),
  );

  logger.info('Updated ${result}');
  return null;
}

String _generateId() {
  return 'test-${DateTime.now().millisecondsSinceEpoch}_it';
}
