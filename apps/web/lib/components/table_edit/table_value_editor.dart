import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../utils/photo_edit_value.dart';
import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';
import 'table_edit_big_int_field.dart';
import 'table_edit_boolean_field.dart';
import 'table_edit_chip_input.dart';
import 'table_edit_datetime_field.dart';
import 'table_edit_enum_multi_select.dart';
import 'table_edit_enum_single_select.dart';
import 'table_edit_json_field.dart';
import 'table_edit_password_field.dart';
import 'table_edit_photo_field.dart';
import 'table_edit_number_field.dart';
import 'table_foreign_key_value_field.dart';

/// Shared type-aware value editor for row detail edit and filter panels.
class TableValueEditor extends StatelessComponent {
  const TableValueEditor({
    super.key,
    required this.id,
    required this.shape,
    this.value,
    this.textValue = '',
    this.boolValue = false,
    this.disabled = false,
    this.labelId,
    this.onTextChanged,
    this.onDraftChanged,
    this.onBoolChanged,
    this.onBrowse,
    this.inputClass,
    this.enumMultiSelect = false,
    this.datetimeCompact = false,
    this.datetimeUseUtc = false,
    this.allowNullableEnum = false,
    this.chipPlaceholder,
    this.fkLayout = TableForeignKeyLayout.row,
    this.fkDisplayLabel,
    this.fkValidationError,
    this.fkValidationLoading = false,
  });

  final String id;
  final ColumnShape shape;
  final Object? value;
  final String textValue;
  final bool boolValue;
  final bool disabled;
  final String? labelId;
  final void Function(String text)? onTextChanged;
  final void Function(Object? value)? onDraftChanged;
  final void Function(bool? value)? onBoolChanged;
  final VoidCallback? onBrowse;
  final String? inputClass;
  final bool enumMultiSelect;
  final bool datetimeCompact;
  final bool datetimeUseUtc;
  final bool allowNullableEnum;
  final String? chipPlaceholder;
  final TableForeignKeyLayout fkLayout;
  final String? fkDisplayLabel;
  final String? fkValidationError;
  final bool fkValidationLoading;

  @override
  Component build(BuildContext context) {
    final shape = this.shape;
    final onText = onTextChanged ?? (_) {};
    final onDraft = onDraftChanged ?? (_) {};
    final onBool = onBoolChanged ?? (_) {};

    final editKind = effectiveColumnEditKind(shape, value);

    if (enumMultiSelect && shape.kind == ColumnShapeKind.enum_) {
      return TableEditEnumMultiSelect(
        id: id,
        enumValues: shape.enumValues,
        valueText: textValue,
        onValueTextChanged: onText,
        labelId: labelId,
      );
    }

    if (isPasswordColumn(shape)) {
      return _passwordEditor(onText);
    }

    return switch (editKind) {
      ColumnShapeKind.boolean || ColumnShapeKind.isVerified => TableEditBooleanField(
        id: id,
        value: _boolDraftValue(value, boolValue),
        onChanged: (v) {
          if (onDraftChanged != null) {
            onDraft(v);
          } else {
            onBool(v ?? false);
          }
        },
        labelId: labelId,
        allowNullable: shape.isNullable,
        disabled: disabled,
      ),
      ColumnShapeKind.enum_ => TableEditEnumSingleSelect(
        id: id,
        enumValues: shape.enumValues,
        value: textValue,
        onChange: onText,
        labelId: labelId,
        allowNullable: allowNullableEnum || shape.isNullable,
        disabled: disabled,
      ),
      ColumnShapeKind.dateTime => TableEditDatetimeField(
        id: id,
        valueText: textValue,
        onValueTextChanged: onText,
        labelId: labelId,
        placeholder: 'Choose date and time',
        compact: datetimeCompact,
        useUtc: datetimeUseUtc,
      ),
      ColumnShapeKind.bigInt => TableEditBigIntField(
        id: id,
        shape: shape,
        value: textValue.isNotEmpty ? textValue : formatBigIntCellString(value),
        onInput: onText,
        labelId: labelId,
        placeholder: shape.isNullable ? 'Leave empty for null' : 'Value',
        disabled: disabled,
        inputClass: inputClass,
      ),
      ColumnShapeKind.integer || ColumnShapeKind.real => TableEditNumberField(
        id: id,
        shape: shape,
        value: textValue,
        onInput: onText,
        labelId: labelId,
        placeholder: shape.isNullable ? 'Leave empty for null' : 'Value',
      ),
      ColumnShapeKind.list => TableEditChipInput(
        id: id,
        valueText: onDraftChanged != null ? joinCommaSeparatedList(cellValueAsStringList(value)) : textValue,
        onValueTextChanged: onDraftChanged != null ? (text) => onDraft(parseCommaSeparatedList(text)) : onText,
        placeholder: chipPlaceholder ?? 'Add value…',
        labelId: labelId,
        disabled: disabled,
      ),
      ColumnShapeKind.enumList => TableEditEnumMultiSelect(
        id: id,
        enumValues: shape.enumValues,
        valueText: onDraftChanged != null
            ? joinCommaSeparatedList(cellValueAsStringList(value, shape.enumValues))
            : textValue,
        onValueTextChanged: onDraftChanged != null ? (text) => onDraft(parseCommaSeparatedList(text)) : onText,
        labelId: labelId,
      ),
      ColumnShapeKind.map => TableEditJsonField(
        id: id,
        value: textValue,
        onInput: onText,
        labelId: labelId,
        placeholder: shape.isNullable ? 'Leave empty for null, or {"key": "value"}' : '{"key": "value"}',
        disabled: disabled,
        inputClass: inputClass,
        validateAsMap: true,
        allowEmpty: shape.isNullable,
      ),
      ColumnShapeKind.photo || ColumnShapeKind.photos => TableEditPhotoField(
        id: id,
        shape: shape,
        value:
            asPhotoEditValue(value) ??
            (value == null ? emptyPhotoEditValue(shape) : photoEditValueFromCell(value, shape)),
        onChanged: (v) => onDraft(v),
        labelId: labelId,
        disabled: disabled,
      ),
      ColumnShapeKind.blob => TableEditJsonField(
        id: id,
        value: textValue,
        onInput: onText,
        labelId: labelId,
        placeholder: shape.isNullable ? 'Leave empty for null' : 'JSON byte array',
        disabled: disabled,
        inputClass: inputClass,
      ),
      _ when isForeignKeyColumn(shape) && onBrowse != null => TableForeignKeyValueField(
        id: id,
        shape: shape,
        textValue: textValue,
        onTextChanged: onText,
        onBrowse: onBrowse!,
        labelId: labelId,
        disabled: disabled,
        layout: fkLayout,
        inputClass: inputClass,
        displayLabel: fkDisplayLabel,
        validationError: fkValidationError,
        validationLoading: fkValidationLoading,
      ),
      _ => _plainTextEditor(shape, onText),
    };
  }

  bool? _boolDraftValue(Object? draftValue, bool filterBool) {
    if (onDraftChanged != null) {
      if (draftValue == null) return null;
      return cellEditValueAsBool(draftValue);
    }
    return filterBool;
  }

  Component _passwordEditor(void Function(String text) onText) {
    return TableEditPasswordField(
      id: id,
      value: textValue,
      onChanged: onText,
      labelId: labelId,
      placeholder: shape.isNullable ? 'Leave empty to keep unchanged' : 'Enter value',
      disabled: disabled,
      inputClass: inputClass,
    );
  }

  Component _plainTextEditor(ColumnShape shape, void Function(String text) onText) {
    final attrs = Map<String, String>.from(validationAttributesForShape(shape));
    final inputType = attrs.remove('type');
    return input<String>(
      id: id,
      type: inputType == 'email' ? .email : .text,
      classes: inputClass ?? ZonaiClasses.input,
      attributes: {
        ...attrs,
        if (labelId != null) 'aria-labelledby': labelId!,
        if (shape.isNullable) 'placeholder': 'Leave empty for null',
        'autocomplete': 'off',
      },
      value: textValue,
      disabled: disabled,
      onInput: onText,
    );
  }
}
