import 'package:zonai/src/domain/gen/client_schema_document.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';

/// The header every generated file carries, matching the precedent set by
/// `lib/src/internal/internal_db_migrations.dart`.
///
/// Half of the write guard: the manifest tells the *generator* what it owns,
/// this tells a *human* who opened the file by mistake.
const kGeneratedClientHeader = '// GENERATED CODE - DO NOT MODIFY BY HAND';

/// Everything an emitter is given. Deliberately just the schema and the
/// config — an emitter that needed a live database would be one that could not
/// run in `--check`.
final class ClientGenerationInput {
  const ClientGenerationInput({
    required this.schema,
    required this.settings,
    required this.generatorVersion,
  });

  final ClientSchemaDocument schema;
  final ClientSettings settings;
  final String generatorVersion;
}

/// Turns a schema into files. The seam the real Dart emitter plugs into.
///
/// Returns file *contents* keyed by path relative to the output directory —
/// not writes. Everything downstream (the manifest, the guard, `--check`)
/// needs to compare a generation against disk without performing it, and that
/// is only possible while the output is still a value.
abstract interface class ClientEmitter {
  Map<String, String> emit(ClientGenerationInput input);
}
