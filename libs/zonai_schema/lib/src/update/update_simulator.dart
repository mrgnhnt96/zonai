import 'dart:convert';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/column_types/created_at_column.dart';
import 'package:zonai_schema/src/column_types/list_column.dart';
import 'package:zonai_schema/src/column_types/map_column.dart';
import 'package:zonai_schema/src/column_types/updated_at_column.dart';
import 'package:zonai_schema/src/column_types/updated_when_column.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';
import 'package:zonai_schema/src/update/update.dart';

/// Computes the row [Update]s would produce when applied to a row, without
/// running any SQL.
///
/// Mirrors `TableOperations.update`'s dispatch over [ColumnUpdate]/
/// [ObjectUpdate]/[UpdateValue] exactly — same guard-rails, same JSON list
/// (append/remove/concat/remove-all) and JSON map (nested `json_set`-style
/// set, RFC 7396 merge patch) semantics — but produces a plain Dart value
/// instead of an `rd.SQL` fragment, so it can run inside the rules worker
/// ahead of the real write.
///
/// JSON list/map mutations are applied directly against the parsed JSON
/// (`jsonDecode`/`jsonEncode`), not through the column's typed
/// `decode`/`encode` — those round-trip through the column's app-level type
/// (e.g. a `mapAs` custom class), which a freshly-built `List`/`Map` value
/// doesn't reify as, and `ListTransformer`/`MapTransformer.encode` are just
/// `jsonEncode` regardless of that type. This mirrors the real SQL builders,
/// which also mutate raw JSON text and only decode to the app type on read.
///
/// Server-managed columns (`createdAt`/`updatedAt`/`updatedWhen`) are left
/// untouched (`after` matches `before` for those columns): their real value
/// is wall-clock write time, which isn't meaningfully simulatable ahead of
/// the actual write, and — like the real update builder — any [Update]
/// naming one of them directly is silently ignored rather than applied.
extension TableUpdateSimulation<S extends rd.Schema<R>, R>
    on rd.TableMeta<S, R> {
  Map<String, Object?> simulateUpdate(
    Map<String, Object?> before,
    List<Update> updates,
  ) {
    final after = <String, Object?>{...before};

    final inferredColumns = <String>{};
    for (final column in columns) {
      switch (column.transformer) {
        case CreatedAtTransformer():
        case UpdatedAtTransformer():
        case UpdatedWhenTransformer():
          inferredColumns.add(column.name);
        case _:
      }
    }

    updateLoop:
    for (final update in updates) {
      switch (update) {
        case ColumnUpdate(:final column, :final value):
          final pathParts = column.split('.');
          if (pathParts.length == 1) {
            if (inferredColumns.contains(column)) {
              continue updateLoop;
            }
            _applyColumnValue(after, column, value);
          } else {
            if (pathParts.any((p) => p.isEmpty)) {
              throw ArgumentError.value(
                column,
                'column',
                'Dotted column path must not contain empty segments',
              );
            }
            final base = pathParts.first;
            if (inferredColumns.contains(base)) {
              continue updateLoop;
            }
            _applyNestedJsonPathUpdate(after, pathParts, value, column);
          }
        case final ObjectUpdate update:
          for (final MapEntry(:key, :value) in update.object.entries) {
            if (inferredColumns.contains(key)) {
              continue;
            }

            if (tryParseUpdateValue(value) case final nested?) {
              _applyColumnValue(after, key, nested);
            } else {
              final col = _requireSimColumn(key);
              if (col.transformer is MapTransformer && value is Map) {
                final current = _decodeJsonMap(after[key]);
                after[key] = jsonEncode(
                  _rfc7396MergePatch(current, Map<String, dynamic>.from(value)),
                );
              } else {
                after[key] = col.encode(col.decode(value));
              }
            }
          }
      }
    }

    return after;
  }

  rd.Column<R, dynamic> _requireSimColumn(String name) {
    for (final column in columns) {
      if (column.name == name) return column;
    }
    throw ColumnNotFoundException(table: this.name, columnName: name);
  }

  void _applyColumnValue(
    Map<String, Object?> after,
    String columnName,
    UpdateValue value,
  ) {
    final col = _requireSimColumn(columnName);
    switch (value) {
      case Literal(:final value):
        after[columnName] = col.encode(col.decode(value));
      case Increment():
        if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Increment is not supported on JSON map columns: $columnName',
          );
        }
        after[columnName] = _numAdd(after[columnName], 1);
      case Decrement():
        if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Decrement is not supported on JSON map columns: $columnName',
          );
        }
        after[columnName] = _numSub(after[columnName], 1);
      case Add(:final value):
        if (col.transformer is ListTransformer) {
          final current = _decodeJsonList(after[columnName]);
          after[columnName] = jsonEncode([...current, value]);
        } else if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Add is not supported on JSON map columns: $columnName',
          );
        } else {
          after[columnName] = _numAdd(after[columnName], value);
        }
      case Remove(:final value):
        if (col.transformer is ListTransformer) {
          final current = _decodeJsonList(after[columnName]);
          after[columnName] = jsonEncode(
            current.where((e) => e != value).toList(),
          );
        } else if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Remove is not supported on JSON map columns: $columnName',
          );
        } else {
          after[columnName] = _numSub(after[columnName], value);
        }
      case AddAll(:final values):
        if (col.transformer is! ListTransformer) {
          throw ArgumentError(
            'AddAll is only supported on list columns (ListTransformer): '
            '$columnName',
          );
        }
        final current = _decodeJsonList(after[columnName]);
        after[columnName] = jsonEncode([...current, ...values]);
      case RemoveAll(:final values):
        if (col.transformer is! ListTransformer) {
          throw ArgumentError(
            'RemoveAll is only supported on list columns (ListTransformer): '
            '$columnName',
          );
        }
        final current = _decodeJsonList(after[columnName]);
        after[columnName] = jsonEncode(
          current.where((e) => !values.contains(e)).toList(),
        );
    }
  }

  void _applyNestedJsonPathUpdate(
    Map<String, Object?> after,
    List<String> pathParts,
    UpdateValue value,
    String columnSpec,
  ) {
    final base = pathParts.first;
    final col = _requireSimColumn(base);
    if (col.transformer is! MapTransformer) {
      throw ArgumentError(
        'Dotted column "$columnSpec" is only supported on JSON map columns '
        '("${col.name}"): use SchemaBuilder.map / mapAs. '
        'Got ${col.transformer.runtimeType}.',
      );
    }
    if (value is! Literal) {
      throw ArgumentError(
        'Only literal UpdateValue is supported for nested JSON map paths '
        '("$columnSpec"): ${value.runtimeType}',
      );
    }

    final current = _decodeJsonMap(after[base]);
    after[base] = jsonEncode(
      _setAtPath(current, pathParts.sublist(1), value.value),
    );
  }
}

/// Decodes a column's raw stored value (JSON text, or already a `List`) as a
/// plain list, treating a missing/null column as `[]` — matching
/// `COALESCE(col, '[]')` in the real SQL builders.
List<dynamic> _decodeJsonList(Object? raw) {
  if (raw == null) return <dynamic>[];
  if (raw is List) return raw;
  if (raw is String) {
    if (raw.isEmpty) return <dynamic>[];
    return jsonDecode(raw) as List<dynamic>;
  }
  throw ArgumentError.value(raw, 'raw', 'Expected JSON text or List');
}

/// Decodes a column's raw stored value (JSON text, or already a `Map`) as a
/// plain map, treating a missing/null column as `{}` — matching
/// `COALESCE(col, '{}')` in the real SQL builders.
Map<String, dynamic> _decodeJsonMap(Object? raw) {
  if (raw == null) return <String, dynamic>{};
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String) {
    if (raw.isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
  throw ArgumentError.value(raw, 'raw', 'Expected JSON text or Map');
}

/// `json_set(COALESCE(col,'{}'), path, value)` equivalent — sets the value at
/// the nested [path], creating missing intermediate objects along the way.
Map<String, dynamic> _setAtPath(
  Map<String, dynamic> target,
  List<String> path,
  Object? value,
) {
  if (path.length == 1) {
    return {...target, path.single: value};
  }

  final key = path.first;
  final rest = path.sublist(1);
  final existing = target[key];
  final nested = existing is Map
      ? Map<String, dynamic>.from(existing)
      : <String, dynamic>{};

  return {...target, key: _setAtPath(nested, rest, value)};
}

/// `json_patch(COALESCE(col,'{}'), patch)` equivalent — RFC 7396 JSON merge
/// patch: a `null` value deletes the key, an object value merges recursively,
/// anything else replaces.
Map<String, dynamic> _rfc7396MergePatch(
  Map<String, dynamic> target,
  Map<String, dynamic> patch,
) {
  final result = {...target};
  for (final entry in patch.entries) {
    if (entry.value == null) {
      result.remove(entry.key);
    } else if (entry.value is Map && result[entry.key] is Map) {
      result[entry.key] = _rfc7396MergePatch(
        Map<String, dynamic>.from(result[entry.key] as Map),
        Map<String, dynamic>.from(entry.value as Map),
      );
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

/// `col + delta` — NULL propagates like SQL arithmetic.
Object? _numAdd(Object? current, Object? delta) {
  if (current == null || delta == null) return null;
  return (current as num) + (delta as num);
}

/// `col - delta` — NULL propagates like SQL arithmetic.
Object? _numSub(Object? current, Object? delta) {
  if (current == null || delta == null) return null;
  return (current as num) - (delta as num);
}
