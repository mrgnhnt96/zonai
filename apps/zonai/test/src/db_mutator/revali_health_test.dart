import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/db_mutator/revali.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';

final _settings = Settings(
  path: 'zonai.yaml',
  migrationsPath: '.zonai/migrations',
  dataPath: '.zonai/data',
  schemasPath: 'lib/src/schemas',
  extensionsPath: 'lib/src/extensions',
  rulesPath: 'lib/src/rules',
  operationsPath: 'lib/src/operations',
  configPath: 'lib/src/config',
  emailTemplatesPath: 'lib/src/email_templates',
  rateLimitPath: 'lib/src/rate_limit',
  cronsPath: 'lib/src/crons',
  imagesPath: '.zonai/data/images',
  buildSettings: BuildSettings.current(),
  version: kVersion,
);

void main() {
  group('Revali.health', () {
    test(
      'reports healthy for the configured port, not the default 8080',
      () async {
        final server = await HttpServer.bind('localhost', 0);
        addTearDown(server.close);
        server.listen((request) {
          request.response
            ..statusCode = 200
            ..close();
        });

        final isHealthy = await runScoped(
          () => Revali().health(),
          values: {
            argsProvider.overrideWith(() => Args(args: {'port': server.port})),
            settingsProvider.overrideWith(() => _settings),
          },
        );

        expect(isHealthy, isTrue);
      },
    );

    test(
      'reports unhealthy when the configured port has nothing listening',
      () async {
        // Grab a port the OS reports as free, then release it immediately --
        // nothing in this test binds to it.
        final probe = await HttpServer.bind('localhost', 0);
        final freePort = probe.port;
        await probe.close();

        final isHealthy = await runScoped(
          () => Revali().health(),
          values: {
            argsProvider.overrideWith(() => Args(args: {'port': freePort})),
            settingsProvider.overrideWith(() => _settings),
          },
        );

        expect(isHealthy, isFalse);
      },
    );
  });
}
