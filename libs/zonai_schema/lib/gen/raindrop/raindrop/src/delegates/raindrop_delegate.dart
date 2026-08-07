// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

part of 'delegates.dart';

/// {@template raindrop_delegate}
/// Base class for providing delegation between a [RaindropExecutor] and the
/// SQL database.
/// {@endtemplate}
abstract class RaindropDelegate extends Delegate {
  /// {@macro raindrop_delegate}
  RaindropDelegate({required SqlDialect dialect}) : super(dialect);
}
