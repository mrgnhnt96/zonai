// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Provide a `NOT` inversion to an known [filter].
Not not(Filter filter) => Not._(filter);

/// {@template not}
/// Inverts a filter.
/// {@endtemplate}
class Not extends Filter {
  /// {@macro not}
  const Not._(this.invert);

  /// The filter to invert.
  final Filter invert;
}
