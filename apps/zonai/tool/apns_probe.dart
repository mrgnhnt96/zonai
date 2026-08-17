// Checks an APNs auth key against **real** Apple, and — unlike its FCM
// sibling — can deliver a real notification safely, because APNs has a
// sandbox and FCM does not.
//
// Usage:
//   dart run tool/apns_probe.dart <AuthKey.p8> <keyId> <teamId> <bundleId> \
//       <deviceToken> [--production]
//
// Defaults to `api.sandbox.push.apple.com`. A token issued to a development
// build is unknown to production and vice versa, and the symptom either way
// is `BadDeviceToken` on a token that is perfectly valid — just not there.
//
// Prints the raw status and `reason` before zonai's own reading of them. The
// FCM classification table was written from documentation and turned out to
// be wrong three times; this one is written the same way, so the first thing
// it should report is what Apple actually said.
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:http2/http2.dart';
import 'package:zonai/src/push/apns_provider_token.dart';
import 'package:zonai/src/push/apns_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai_schema/zonai_schema.dart';

Future<void> main(List<String> args) async {
  if (args.length < 5) {
    stderr.writeln(
      'usage: dart run tool/apns_probe.dart <AuthKey.p8> <keyId> <teamId> '
      '<bundleId> <deviceToken> [--production]',
    );
    exit(64);
  }

  final [keyPath, keyId, teamId, bundleId, deviceToken, ...rest] = args;
  final production = rest.contains('--production');

  if (!File(keyPath).existsSync()) {
    stderr.writeln('no such key file: $keyPath');
    exit(66);
  }

  final config = PushConfig(
    apns: ApnsConfig(
      credentials: ApnsCredentials.file(keyPath),
      keyId: keyId,
      teamId: teamId,
      bundleId: bundleId,
      useSandbox: !production,
    ),
    concurrency: 1,
  );

  stdout
    ..writeln('key      : $keyPath')
    ..writeln('keyId    : $keyId')
    ..writeln('teamId   : $teamId')
    ..writeln('topic    : $bundleId')
    ..writeln('host     : ${config.apns!.host}')
    ..writeln(
      'device   : ${deviceToken.length > 24 ? '${deviceToken.substring(0, 24)}…' : deviceToken}',
    )
    ..writeln('');

  // Ground truth first, before zonai's reading of it gets a say. The FCM
  // classification table was written from documentation and was wrong three
  // times; printing only our enum can agree with the same mistake and look
  // like confirmation of it.
  await _raw(
    keyPem: File(keyPath).readAsStringSync(),
    config: config.apns!,
    deviceToken: deviceToken,
  );

  final courier = ApnsPushCourier(fileSystem: const LocalFileSystem());
  try {
    final outcomes = await courier.send(
      const PushMessage(
        title: 'zonai',
        body: 'sent straight to APNs, no Firebase in the path',
      ),
      [deviceToken],
      config: config,
    );

    switch (outcomes.single) {
      case PushDelivered():
        stdout
          ..writeln('✓ ACCEPTED BY APPLE')
          ..writeln('  APNs took the notification for this device. That is')
          ..writeln('  as far as any sender can see — delivery to the screen')
          ..writeln('  is between Apple and the device.');
      case PushPermanentlyRejected(:final reason):
        stdout
          ..writeln('✗ REJECTED — $reason')
          ..writeln('  Read the raw reason above rather than this line: the')
          ..writeln('  same outcome covers several causes. BadDeviceToken is')
          ..writeln('  usually the right token in the wrong world (sandbox')
          ..writeln('  tokens are unknown to production and the reverse — try')
          ..writeln('  --production), while Unregistered means the app really')
          ..writeln('  is gone from that device.');
      case PushTransientlyFailed(:final detail):
        stdout
          ..writeln('~ TRANSIENT — $detail')
          ..writeln('  Retry; nothing here says the key or the token is bad.');
    }
  } on PushTransportException catch (e) {
    stdout
      ..writeln('✗ PROVIDER TOKEN REJECTED')
      ..writeln('  $e')
      ..writeln('')
      ..writeln('  The key id, the team id and the .p8 have to agree. A .p8')
      ..writeln('  carries no id inside it, so a renamed file is the usual')
      ..writeln(
        '  cause — the filename is the only record of which key it is.',
      );
    exitCode = 1;
  } finally {
    await courier.close();
  }
}

/// Sends once over raw HTTP/2 and prints Apple's untouched status and reason.
Future<void> _raw({
  required String keyPem,
  required ApnsConfig config,
  required String deviceToken,
}) async {
  try {
    final providerToken = ApnsProviderToken(
      privateKeyPem: keyPem,
      keyId: config.keyId,
      teamId: config.teamId,
    ).get();

    final socket = await SecureSocket.connect(
      config.host,
      443,
      supportedProtocols: const ['h2'],
    );
    final connection = ClientTransportConnection.viaSocket(socket);

    final body = utf8.encode(
      jsonEncode({
        'aps': {
          'alert': {'title': 'zonai', 'body': 'direct to APNs'},
        },
      }),
    );

    final stream =
        connection.makeRequest([
            Header.ascii(':method', 'POST'),
            Header.ascii(':scheme', 'https'),
            Header.ascii(':authority', config.host),
            Header.ascii(':path', '/3/device/$deviceToken'),
            Header.ascii('authorization', 'bearer $providerToken'),
            Header.ascii('apns-topic', config.bundleId),
            Header.ascii('apns-push-type', 'alert'),
          ], endStream: false)
          ..outgoingMessages.add(DataStreamMessage(body, endStream: true));
    await stream.outgoingMessages.close();

    var status = 0;
    final response = StringBuffer();
    await for (final incoming in stream.incomingMessages) {
      switch (incoming) {
        case HeadersStreamMessage(:final headers):
          for (final header in headers) {
            if (ascii.decode(header.name) == ':status') {
              status = int.tryParse(ascii.decode(header.value)) ?? 0;
            }
          }
        case DataStreamMessage(:final bytes):
          response.write(utf8.decode(bytes, allowMalformed: true));
      }
    }
    await connection.finish();

    stdout
      ..writeln('--- what Apple actually said ---')
      ..writeln('HTTP   : $status')
      ..writeln(
        'body   : ${response.isEmpty ? '(empty — accepted)' : response}',
      )
      ..writeln('');
  } catch (e) {
    stdout.writeln('raw probe failed: $e\n');
  }
}
