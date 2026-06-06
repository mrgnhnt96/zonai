import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/table_cell_edit.dart';
import 'foreign_key_rows_provider.dart';
import 'table_schema_provider.dart';

/// Result of checking whether a typed FK value exists in the referenced table.
enum ForeignKeyReferenceValidation { idle, loading, valid, invalid }

/// Parameters for [foreignKeyReferenceValidateProvider].
final class ForeignKeyReferenceValidateQuery {
  const ForeignKeyReferenceValidateQuery({
    required this.foreignKey,
    required this.columnShape,
    required this.valueText,
  });

  final ForeignKeyShape foreignKey;
  final ColumnShape columnShape;
  final String valueText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForeignKeyReferenceValidateQuery &&
          foreignKey == other.foreignKey &&
          columnShape == other.columnShape &&
          valueText == other.valueText;

  @override
  int get hashCode => Object.hash(foreignKey, columnShape, valueText);
}

/// Validates that [valueText] references an existing row (debounced by the caller).
final foreignKeyReferenceValidateProvider =
    FutureProvider.family<ForeignKeyReferenceValidationResult, ForeignKeyReferenceValidateQuery>((ref, query) async {
      if (!ref.binding.isClient) {
        return const ForeignKeyReferenceValidationResult(state: ForeignKeyReferenceValidation.idle);
      }

      final trimmed = query.valueText.trim();
      if (trimmed.isEmpty) {
        return const ForeignKeyReferenceValidationResult(state: ForeignKeyReferenceValidation.valid);
      }

      Object? parsed;
      try {
        parsed = parseEditValue(draftValue: null, textInput: trimmed, shape: query.columnShape);
      } on FormatException {
        return const ForeignKeyReferenceValidationResult(state: ForeignKeyReferenceValidation.invalid);
      }

      if (parsed == null) {
        return const ForeignKeyReferenceValidationResult(state: ForeignKeyReferenceValidation.valid);
      }

      final schema = ref.watch(tableSchemasProvider)[query.foreignKey.table];
      final referenced = await loadForeignKeyReferencedRow(
        foreignKey: query.foreignKey,
        parsedValue: parsed,
        schema: schema,
      );
      if (referenced == null) {
        return const ForeignKeyReferenceValidationResult(state: ForeignKeyReferenceValidation.invalid);
      }

      return ForeignKeyReferenceValidationResult(
        state: ForeignKeyReferenceValidation.valid,
        displayLabel: referenced.displayLabel,
      );
    });

final class ForeignKeyReferenceValidationResult {
  const ForeignKeyReferenceValidationResult({required this.state, this.displayLabel});

  final ForeignKeyReferenceValidation state;
  final String? displayLabel;
}
