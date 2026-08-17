import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/server/lib/config/server_binding.dart';
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
        // Bind what the probe will dial, not a name that resolves to it on
        // some machines. This test is about the *port*; the host was
        // incidental, and it worked only because `ServerBinding.host` used to
        // answer the wildcard `::`, which sends the probe at both loopbacks.
        // Since the bind-exposure fix it answers `127.0.0.1` and probes that
        // alone, while `bind('localhost')` picks whichever family the
        // resolver puts first -- `::1` on macOS. The server was listening and
        // the probe was looking elsewhere.
        final server = await HttpServer.bind(ServerBinding.host, 0);
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
        // nothing in this test binds to it. Same host as the case above, so
        // the port is known free on the address the probe actually dials.
        final probe = await HttpServer.bind(ServerBinding.host, 0);
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
