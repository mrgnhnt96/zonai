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
    logger.info('SEND TEST EMAIL');
    final email = Email(
      to: EmailAddress(address: 'mrgnhnt96+test@gmail.com', name: 'Test User'),
      subject: 'Test Email',
      template: 'verify_email',
      variables: {
        'name': 'Test User',
        'verificationUrl': 'https://www.google.com',
        'expiresIn': '1 hour',
        'email': 'mrgnhnt96+test@gmail.com',
      },
    );

    await zonaiDB.sendTestEmail(email);
    logger.info('Test email sent');
  }

  {
    logger.info('--------------------------------');
    logger.info('SIGN IN');
    final (exitCode, signedInJwt) = await _signIn(email);
    if (exitCode != null || signedInJwt == null) {
      return exitCode ?? 1;
    }

    jwt = signedInJwt;
  }

  {
    logger.info('--------------------------------');
    logger.info('ADMIN SIGN IN');
    final (exitCode, signedInJwt) = await _adminSignIn(email);
    if (exitCode != null || signedInJwt == null) {
      return exitCode ?? 1;
    }
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

  logger.info('STREAM COUNT');
  if (await _streamCount(jwt: jwt) case final int exitCode) {
    return exitCode;
  }
  logger.info('--------------------------------');

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

  logger.info('EXPANDING RECORD');
  if (await _expand(jwt: jwt) case final int exitCode) {
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

  final result = await zonaiDB.authenticate(
    'users',
    SignUpPasswordAuthPayload(
      email: email,
      password: 'test',
      object: {'name': 'Test User'},
    ),
  );

  logger.info('Signed up user: ${result!.user['Id']}');

  return (null, email);
}

Future<(int?, String?)> _signIn(String email) async {
  final result = await zonaiDB.authenticate(
    'users',
    SignInPasswordAuthPayload(email: email, password: 'test'),
  );

  logger.info('Signed in user: ${result!.user['id']}');

  return (null, result.jwt);
}

Future<(int?, String?)> _adminSignIn(String email) async {
  final authTypes = await zonaiDB.adminSupportedAuthTypes();
  logger.info(
    'Supported auth types (${authTypes.length}): ${authTypes.map((e) => e.name).join(', ')}',
  );
  final result = await zonaiDB.authenticateAdmin(
    SignInPasswordAuthPayload(email: email, password: 'test'),
  );

  logger.info('Signed in user: ${result!.user['id']}');

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

  logger.info('Authenticated user: ${result!.user['id']}');

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
    .new(jwt: jwt, where: NotContains('body', 'Test'), limit: 20),
  );

  logger.info('Found ${result.items.length}/${result.total} records');
  for (final record in result.items) {
    logger.info('Record: ${record}');
  }
  return (null, result.items.last['id'] as String?);
}

Future<(int?, int?)> _count({required String jwt}) async {
  final result = await zonaiDB.count(
    'items',
    .new(jwt: jwt, where: NotNull('id')),
  );

  logger.info('Found ${result} records');
  return (null, result);
}

Future<int?> _streamCount({required String jwt}) async {
  // Isolate to a fresh id so the count reacts 0→1 and we are not sensitive to DB
  // size or scheduling (the global-count stream often emits only after create
  // returns, making "first emission baseline" unreliable).
  final probeId = _generateId();
  final countPayload = CountPayload(jwt: jwt, where: Eq('id', probeId));
  final beforeCount = await zonaiDB.count('items', countPayload);

  final completer = Completer<void>();
  final listener =
      zonaiDB.streamCount('items', countPayload).listen((count) {
        logger.info('Stream count: $count');

        // At least one new row matched (beforeCount should be 0 for probeId).
        if (count >= beforeCount + 1 && !completer.isCompleted) {
          completer.complete();
        }
      })..onError((e, stack) {
        logger.error('Stream error', e, stack);
      });

  await zonaiDB.create(
    'items',
    .new(jwt: jwt, object: {'body': 'Stream count probe', 'id': probeId}),
  );

  await completer.future;
  listener.cancel().ignore();
  return null;
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

Future<int?> _expand({required String jwt}) async {
  const authorName = 'Expand Test Author';
  const postTitle = 'Expand test post';

  final authorId = _generateId(suffix: 'au');
  await zonaiDB.create(
    'authors',
    .new(jwt: jwt, object: {'id': authorId, 'name': authorName}),
  );

  final postId = _generateId(suffix: 'po');
  await zonaiDB.create(
    'posts',
    .new(
      jwt: jwt,
      object: {
        'id': postId,
        'author_id': authorId,
        'title': postTitle,
        'body': 'Expand test body',
      },
    ),
  );

  final expandedPost = await zonaiDB.read(
    'posts',
    .new(jwt: jwt, where: Eq('id', postId), expand: ['author_id']),
  );

  logger.info('Expanded post: $expandedPost');

  if (expandedPost['author_id'] != authorId) {
    logger.error(
      'Expected author_id to remain the FK value "$authorId", got: ${expandedPost['author_id']}',
    );
    return 1;
  }

  final expanded = expandedPost['expanded'];
  if (expanded is! Map<String, Object?>) {
    logger.error('Expected expanded map, got: $expanded');
    return 1;
  }

  final authorField = expanded['author_id'];
  if (authorField is! Map<String, Object?>) {
    logger.error(
      'Expected expanded.author_id to be a record map, got: $authorField',
    );
    return 1;
  }

  if (authorField['name'] != authorName) {
    logger.error(
      'Expanded author name mismatch: expected "$authorName", got "${authorField['name']}"',
    );
    return 1;
  }

  final listedPosts = await zonaiDB.list(
    'posts',
    .new(jwt: jwt, where: Eq('id', postId), expand: ['author_id']),
  );

  final listedPost = listedPosts.items.single;
  if (listedPost['author_id'] != authorId) {
    logger.error(
      'Expected list author_id to remain the FK value "$authorId", got: ${listedPost['author_id']}',
    );
    return 1;
  }

  final listedExpanded = listedPost['expanded'];
  if (listedExpanded is! Map<String, Object?>) {
    logger.error('Expected list expanded map, got: $listedExpanded');
    return 1;
  }

  final listedAuthor = listedExpanded['author_id'];
  if (listedAuthor is! Map<String, Object?>) {
    logger.error(
      'Expected list expanded.author_id to be a record map, got: $listedAuthor',
    );
    return 1;
  }

  if (listedAuthor['name'] != authorName) {
    logger.error(
      'List expanded author name mismatch: expected "$authorName", got "${listedAuthor['name']}"',
    );
    return 1;
  }

  await zonaiDB.delete('posts', .new(jwt: jwt, where: Eq('id', postId)));
  await zonaiDB.delete('authors', .new(jwt: jwt, where: Eq('id', authorId)));

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

String _generateId({String suffix = 'it'}) {
  return 'test-${DateTime.now().millisecondsSinceEpoch}_$suffix';
}
