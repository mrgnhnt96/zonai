// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

// Raw `Selectable`s are intentional: results hold selectables of
// diverse value types.
// ignore_for_file: strict_raw_type

/// Interface for making a class selectable.
///
/// Used internally.
abstract interface class Selectable<V> {}

/// {@template selectable_result}
/// List of selectable results
///
/// Used internally.
/// {@endtemplate}
class SelectableResult<V> implements Selectable<V> {
  /// {@macro selectable_result}
  const SelectableResult(this.selected);

  /// The selected items.
  final List<Selectable> selected;
}
