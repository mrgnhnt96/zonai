import 'dart:async';
import 'dart:math';

import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../../db_mutator/payloads/payloads.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/settings.dart';
import '../../deps/zonai_db.dart';

/// Minimal JPEG bytes (SOI + EOI) for upload smoke tests.
const testImageBytes = [0xFF, 0xD8, 0xFF, 0xD9];

/// Distinct bytes used to verify PATCH replaces the on-disk image.
const updatedImageBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9];

Future<int> photos() async {
  logger.info('SIGN UP');
  final (exitCode, email) = await _signUp();
  if (exitCode != null || email == null) {
    return exitCode ?? 1;
  }

  logger.info('--------------------------------');
  logger.info('SIGN IN');
  final (signInExitCode, jwt, _) = await _signIn(email);
  if (signInExitCode != null || jwt == null) {
    return signInExitCode ?? 1;
  }

  logger.info('--------------------------------');
  logger.info('PHOTOS');
  if (await verifyPhotoUploads(jwt: jwt) case final int exitCode) {
    return exitCode;
  }

  logger.info('--------------------------------');
  logger.info('Photo upload verification passed');
  return 0;
}

/// Returns a stream one byte over [maxBytes] for limit enforcement checks.
Stream<List<int>> oversizedImage(int maxBytes) =>
    Stream.value(List.filled(maxBytes + 1, 0));

/// Exercises create, view, update, and delete for photo uploads.
///
/// Returns a non-zero exit code on failure, or `null` on success.
Future<int?> verifyPhotoUploads({required String jwt}) async {
  final createMeta = PhotoCreateMeta(table: 'items');
  final maxBytes = (await zonaiDB.getConfig()).photos.maxBytes;

  if (maxBytes case final limit?) {
    logger.info('VERIFY MAX BYTES ENFORCED ON CREATE ($limit bytes)');
    try {
      await zonaiDB.createPhoto(
        token: jwt,
        meta: createMeta,
        contentType: 'image/jpeg',
        image: oversizedImage(limit),
      );
      logger.error('Expected oversized create to be rejected');
      return 1;
    } catch (error) {
      logger.info('Oversized create rejected: $error');
    }
  } else {
    logger.info('SKIP MAX BYTES CHECK (maxBytes not configured)');
  }

  logger.info('UPLOAD PHOTO');
  final createResponse = await zonaiDB.createPhoto(
    token: jwt,
    meta: createMeta,
    contentType: 'image/jpeg',
    image: Stream.value(testImageBytes),
  );
  final photoId = createResponse['id'] as String;

  logger.info('Created photo: $photoId');

  logger.info('VERIFY PHOTO FILE CREATED');
  final imageFile = fs.file(
    fs.path.join(settings.imagesPath, 'items', '$photoId.jpg'),
  );
  if (!imageFile.existsSync()) {
    logger.error('Expected photo file to exist: ${imageFile.path}');
    return 1;
  }

  logger.info('Photo file exists: ${imageFile.path}');

  logger.info('VIEW PHOTO');
  final bytes = await zonaiDB.getPhoto(photoId, token: jwt).toList();

  if (!_sameBytes(bytes.expand((e) => e).toList(), testImageBytes)) {
    logger.error(
      'Photo view bytes mismatch: expected ${testImageBytes.length} bytes, got ${bytes.expand((e) => e).toList().length} bytes',
    );
    return 1;
  }

  logger.info(
    'Viewed photo bytes (${bytes.expand((e) => e).toList().length} bytes)',
  );

  logger.info('UPDATE PHOTO');
  await zonaiDB.updatePhoto(
    token: jwt,
    id: photoId,
    image: Stream.value(updatedImageBytes),
  );

  logger.info('Updated photo: $photoId');

  logger.info('VERIFY UPDATED PHOTO BYTES');
  final updatedBytes = await zonaiDB.getPhoto(photoId, token: jwt).toList();
  if (!_sameBytes(updatedBytes.expand((e) => e).toList(), updatedImageBytes)) {
    logger.error(
      'Updated photo bytes mismatch: expected ${updatedImageBytes.length} bytes, got ${updatedBytes.expand((e) => e).toList().length} bytes',
    );
    return 1;
  }

  if (!imageFile.existsSync()) {
    logger.error(
      'Expected photo file to exist before delete: ${imageFile.path}',
    );
    return 1;
  }

  if (maxBytes case final limit?) {
    logger.info('VERIFY MAX BYTES ENFORCED ON UPDATE ($limit bytes)');
    try {
      await zonaiDB.updatePhoto(
        token: jwt,
        id: photoId,
        image: oversizedImage(limit),
      );
      logger.error('Expected oversized update to be rejected');
      return 1;
    } catch (error) {
      logger.info('Oversized update rejected: $error');
    }

    final bytesAfterRejectedUpdate = await zonaiDB
        .getPhoto(photoId, token: jwt)
        .toList();
    if (!_sameBytes(
      bytesAfterRejectedUpdate.expand((e) => e).toList(),
      updatedImageBytes,
    )) {
      logger.error('Photo bytes changed after rejected oversized update');
      return 1;
    }

    logger.info('Photo bytes unchanged after rejected oversized update');
  }

  logger.info('DELETE PHOTO');
  await zonaiDB.deletePhoto(token: jwt, id: photoId);

  logger.info('Deleted photo: $photoId');

  logger.info('VERIFY PHOTO DELETED');
  try {
    await zonaiDB.getPhoto(photoId, token: jwt).toList();
    logger.error('Expected deleted photo to be gone');
    return 1;
  } catch (_) {
    logger.info('Photo deleted correctly');
  }

  logger.info('Photo record correctly removed');

  logger.info('VERIFY PHOTO FILE DELETED');
  if (imageFile.existsSync()) {
    logger.error('Expected photo file to be deleted: ${imageFile.path}');
    return 1;
  }

  logger.info('Photo file correctly removed');

  return null;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }

  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }

  return true;
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

Future<(int?, String?, String?)> _signIn(String email) async {
  final result = await zonaiDB.authenticate(
    'users',
    SignInPasswordAuthPayload(email: email, password: 'test'),
  );

  logger.info('Signed in user: ${result!.user['id']}');

  return (null, result.jwt, result.user['id'] as String?);
}
