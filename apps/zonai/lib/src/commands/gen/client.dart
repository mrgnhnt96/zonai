import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/gen/client_generator.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';

import '../../deps/args.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/settings.dart';
import '../../deps/zonai_db.dart';

const _usage =
    '''
Usage: zonai gen client [options]

Generate a typed Dart client from the project's schema, plus
.zonai/schema.json describing it.

Everything is configured by the `client:` block in zonai.yaml; the flags below
are overrides for one-off and CI use.

Options:
  -h, --help              Show help information
      --check             Write nothing; exit non-zero if the committed output
                          is stale
      --output=<dir>      Override client.output for this run
      --force             Generate into a non-empty directory that has no
                          $_manifestName. Adds files; never deletes
                          files zonai did not write.
  -c, --config=<path>     Path to zonai.yml

The generated files carry a "GENERATED CODE" header and are recorded in
$_manifestName inside the output directory. Regeneration replaces or
removes the files in that manifest and touches nothing else.
''';

const _manifestName = 'zonai_client_manifest.json';

/// The block to add, printed verbatim when `zonai.yaml` has none.
///
/// This is the entire failure mode of "I ran the command and nothing
/// happened": there is no default output directory, and there cannot be one --
/// the destination belongs to an app this project knows nothing about. So the
/// error is the documentation.
const _missingBlock = '''
zonai gen client needs a `client:` block in zonai.yaml -- there is no default
output directory, because the generated client belongs to an app this project
does not depend on.

Add this to zonai.yaml and adjust `output`:

client:
  output: ../app/lib/gen/zonai   # required; where to write the generated client
  package: false                 # true -> also emit a pubspec.yaml
  # packageName: my_api          # only read when package: true
  # tables:
  #   exclude: [audit_log]       # default: every project table
  #   include: [_log]            # opt a zonai system table back in
  # names:
  #   posts:
  #     row: BlogPostsRow        # per-table override of the default naming
''';

/// Same problem, one level in: the block is there but names nowhere to write.
const _missingOutput = '''
zonai gen client needs `client.output` in zonai.yaml -- the `client:` block is
there, but it does not say where to write.

client:
  output: ../app/lib/gen/zonai   # required; where to write the generated client

Or pass --output=<dir> for a one-off run.
''';

Future<int> client() async {
  // Before settings, before the filesystem, before the database. Asking this
  // command how to use it must not generate anything.
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final ClientSettings? configured = settings.client;
  if (configured == null) {
    logger.error(_missingBlock);
    return 1;
  }

  final override = args.getOrNull<String>('output');
  final output = switch ((override, configured.output)) {
    (final String value, _) => fs.path.normalize(value),
    (_, final String value) => value,
    _ => null,
  };

  if (output == null) {
    logger.error(_missingOutput);
    return 1;
  }

  final check = args.getOrNull<bool>('check') ?? false;
  final force = args.getOrNull<bool>('force') ?? false;

  final generator = ClientGenerator(
    settings: configured,
    outputDirectory: output,
    schemaFilePath: settings.clientSchemaPath,
    generatorVersion: kVersion,
  );

  try {
    final shapes = await zonaiDB.schemaShapes();
    final plan = generator.plan(shapes);

    // Named, never silent. Most of a registered schema is zonai's own
    // (`_jwt`, `_rate_limit`, `_photos`, ...), and a generated API over those
    // would read as a supported surface -- so they are left out. A developer
    // who wanted one back has to be able to see that it was dropped, and how
    // to ask for it.
    final skipped = configured.excludedFrom(shapes.keys);
    if (skipped.isNotEmpty) {
      final internal = skipped.where(ClientSettings.isInternalTable).toList();
      logger.info('Skipped ${skipped.length} table(s): ${skipped.join(', ')}');
      if (internal.isNotEmpty) {
        logger.info(
          'Of those, ${internal.length} are zonai\'s own system tables. Add '
          'one to `client.tables.include` in zonai.yaml to generate it anyway.',
        );
      }
    }

    if (plan.schema.tables.isEmpty) {
      logger.warn(
        'No tables to generate from. Every registered table is excluded by '
        'client.tables.exclude, or this project has no schemas.',
      );
    }

    if (check) {
      return _report(generator.check(plan), output);
    }

    if (generator.guard(force: force) case final refusal?) {
      logger.error(refusal.message);
      return 1;
    }

    final result = generator.write(plan);

    logger.info(
      'Generated ${plan.files.length} file(s) for '
      '${plan.schema.tables.length} table(s) in $output',
    );
    logger.info(
      'Wrote ${plan.schemaFilePath} (schema ${_short(plan.schema.hash)})',
    );
    for (final path in result.removed) {
      logger.info('Removed $path (no longer generated)');
    }

    return 0;
  } catch (e, stack) {
    logger.error('Failed to generate the client: $e', e, stack);
    return 1;
  }
}

/// Turns a drift list into something a human can act on.
///
/// "stale" on its own tells a developer to re-run the command; naming the
/// files tells them whether the change was theirs.
int _report(List<ClientDrift> drift, String output) {
  if (drift.isEmpty) {
    logger.info('Generated client is up to date ($output).');
    return 0;
  }

  logger.error(
    'Generated client is stale -- ${drift.length} difference(s). Run '
    '`zonai gen client` and commit the result.',
  );
  for (final entry in drift) {
    logger.error(entry.toString());
  }

  return 1;
}

String _short(String hash) => hash.length <= 12 ? hash : hash.substring(0, 12);
