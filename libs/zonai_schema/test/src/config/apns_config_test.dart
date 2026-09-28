import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group('DevicePlatform', () {
    test('stores each value under its wire name', () {
      expect(
        [for (final p in DevicePlatform.values) p.toJson()],
        ['ios', 'ios-sandbox', 'android'],
      );
    });

    test('parses every wire name back', () {
      for (final platform in DevicePlatform.values) {
        expect(DevicePlatform.tryParse(platform.toJson()), platform);
      }
    });

    test('accepts the spellings client code writes for a sandbox build', () {
      // The column is written by app code Zonai does not control, and the
      // enum's own Dart name is the first thing someone reaches for.
      for (final value in [
        'iosSandbox',
        'IOS-SANDBOX',
        'ios_sandbox',
        ' ios-sandbox ',
      ]) {
        expect(
          DevicePlatform.tryParse(value),
          DevicePlatform.iosSandbox,
          reason: value,
        );
      }
    });

    test('an unrecognised value is null, not an exception', () {
      expect(DevicePlatform.tryParse('ios-staging'), isNull);
    });
  });

  group('ApnsConfig.sandbox', () {
    const production = ApnsConfig(
      credentials: ApnsCredentials.inline('pem'),
      keyId: 'LALL9GMRMP',
      teamId: 'TEAMID1234',
      bundleId: 'dev.zonai.pushProbe',
    );

    test('is the same key and app on the sandbox host', () {
      final sandbox = production.sandbox;

      expect(sandbox.host, ApnsConfig.sandboxHost);
      expect(sandbox.credentials, production.credentials);
      expect(sandbox.keyId, production.keyId);
      expect(sandbox.teamId, production.teamId);
      expect(sandbox.bundleId, production.bundleId);
    });

    test('leaves a config already on the sandbox alone', () {
      final sandbox = production.sandbox;
      expect(identical(sandbox.sandbox, sandbox), isTrue);
    });
  });

  test('PushConfig.withApns changes the APNs config and nothing else', () {
    const config = PushConfig(
      projectId: 'p',
      credentials: PushCredentials.inline('{}'),
      apns: ApnsConfig(
        credentials: ApnsCredentials.inline('pem'),
        keyId: 'LALL9GMRMP',
        teamId: 'TEAMID1234',
        bundleId: 'dev.zonai.pushProbe',
      ),
      onPermanentRejection: OnPermanentRejection.deleteRow,
      batchSize: 7,
      concurrency: 3,
      maxAttemptsPerBatch: 5,
    );

    final swapped = config.withApns(config.apns!.sandbox);

    expect(swapped.apns!.useSandbox, isTrue);
    expect(swapped.toJson()..remove('apns'), config.toJson()..remove('apns'));
  });
}
