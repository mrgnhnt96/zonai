// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:async';

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/src/utils/lock.dart';

part 'raindrop_executor.dart';

/// {@template raindrop}
/// The database class of Raindrop.
///
/// It encapsulates the [RaindropDelegate] in such a way that end-users can
/// change their underlying implementation.
/// {@endtemplate}
class Raindrop extends RaindropExecutor<RaindropDelegate> {
  /// {@macro raindrop}
  Raindrop(super.delegate, {super.logger = const NoopLogger()});

  @override
  Future<DatabaseResult> execute(
    String query, [
    List<Object?> values = const [],
  ]) async {
    return tracer.trace('Raindrop.execute', (span) {
      span?.attributes.addAll({'query': query, 'values': values});
      return super.execute(query, values);
    });
  }

  /// The default tracer used by [Raindrop].
  ///
  /// It is by turned off by default.
  static final tracer = Tracer('raindrop', isTracing: false);
}
