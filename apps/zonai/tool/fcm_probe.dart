// Checks a service-account key against **real** FCM, without delivering a
// notification to anyone.
//
// The gap this exists to close: push credentials fail in three different ways
// that look identical from the outside — wrong project, missing IAM role, FCM
// API not enabled — and all three surface as "notifications just don't
// arrive". Every other way of finding out involves a real device and a real
// send. This asks Google directly.
//
// It sends to a token FCM has never issued, so the only possible reply is an
// error. That is the point: the *error* is the diagnosis. Nothing reaches a
// phone, and nothing is pruned, because the probe never touches a database.
//
// Usage:
//   dart run tool/fcm_probe.dart <service-account.json> [project-id]
//
// `project-id` defaults to the key's own `project_id`, and is worth passing
// explicitly when the FCM project differs from the one the key was minted in
// — a common arrangement, and one of the three failure modes above.
//
// Prints `project_id` and `client_email` for diagnosis. Never prints
// `private_key`: a diagnostic that leaks the key it is diagnosing is worse
// than the fault it was run to find.
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:zonai/src/push/fcm_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Shaped like an FCM registration token but not one, so a send can only
/// ever come back as an error.
const _neverIssued =
    'fDqZoNaIpRoBe:APA91bHzonaiProbeTokenThatWasNeverIssuedByFcm'
    '0000000000000000000000000000000000000000000000000000000000';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/fcm_probe.dart <service-account.json> '
      '[project-id]',
    );
    exit(64);
  }

  final path = args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }

  final Map<String, dynamic> key;
  try {
    key = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('not valid service-account JSON (${e.runtimeType})');
    exit(65);
  }

  final projectId = args.length > 1 ? args[1] : key['project_id'] as String?;

  stdout
    ..writeln('type          : ${key['type']}')
    ..writeln('key project   : ${key['project_id']}')
    ..writeln('client_email  : ${key['client_email']}')
    ..writeln('sending to    : $projectId')
    ..writeln('');

  if (projectId == null) {
    stderr.writeln(
      'the key carries no project_id — pass one as the second argument',
    );
    exit(65);
  }

  final courier = FcmPushCourier(fileSystem: const LocalFileSystem());
  final config = PushConfig(
    projectId: projectId,
    credentials: PushCredentials.file(path),
    concurrency: 1,
  );

  try {
    final outcomes = await courier.send(
      const PushMessage(title: 'zonai probe', body: 'never delivered'),
      const [_neverIssued],
      config: config,
    );

    switch (outcomes.single) {
      // The healthy answer. Credentials work, the project is reachable, and
      // FCM got far enough to judge the token itself.
      case PushPermanentlyRejected(:final reason):
        stdout
          ..writeln('✓ CREDENTIALS WORK — FCM rejected the token, not the key')
          ..writeln('  classified as: $reason')
          ..writeln('')
          ..writeln('  This is the expected result. A token FCM never issued')
          ..writeln('  is exactly what a dead registration looks like, so a')
          ..writeln('  permanent rejection here is the same path that prunes')
          ..writeln('  a real uninstalled device.');
      case PushDelivered():
        stdout.writeln(
          '?? FCM accepted a token it cannot have issued — this should not '
          'happen, and nothing about the classification table should be '
          'trusted until it is explained.',
        );
      case PushTransientlyFailed(:final detail):
        stdout
          ..writeln('~ TRANSIENT — the credentials may be fine')
          ..writeln('  detail: $detail')
          ..writeln('  Retry; a 5xx or a quota reply is not a config fault.');
    }
  } on PushTransportException catch (e) {
    // 401/403 land here by design: they are about the caller, never the
    // token, and zonai fails the whole job rather than blaming recipients.
    stdout
      ..writeln('✗ CREDENTIALS REJECTED')
      ..writeln('  $e')
      ..writeln('')
      ..writeln('  403 PERMISSION_DENIED — the service account lacks the')
      ..writeln('    Firebase Cloud Messaging API Admin role, or the FCM API')
      ..writeln('    is not enabled on this project. A Play/androidpublisher')
      ..writeln('    service account (Play billing, RevenueCat) is a common')
      ..writeln('    false lead: right file, wrong project entirely.')
      ..writeln('  404 — the project id does not exist or has no FCM.')
      ..writeln('  401 — the assertion did not verify; check the clock.');
    exitCode = 1;
  } finally {
    await courier.close();
  }
}
