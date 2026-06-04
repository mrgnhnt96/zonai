import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/table_cell_edit.dart';
import '../utils/table_where_operators.dart';
import 'table_edit/table_edit_chip_input.dart';
import 'table_edit/table_edit_enum_multi_select.dart';
import 'table_filter_datetime_field.dart';
import 'table_edit/table_edit_number_field.dart';
import 'table_edit/table_edit_select.dart';
import 'theme/ui_styles.dart';

/// Value editor for one filter condition row (type-aware).
class TableFilterValueField extends StatelessComponent {
  const TableFilterValueField({
    super.key,
    required this.id,
    required this.shape,
    required this.operator,
    required this.valueText,
    required this.boolValue,
    required this.onValueTextChanged,
    required this.onBoolValueChanged,
    this.labelId,
  });

  final String id;
  final ColumnShape shape;
  final TableWhereOperator operator;
  final String valueText;
  final bool boolValue;
  final void Function(String valueText) onValueTextChanged;
  final void Function(bool boolValue) onBoolValueChanged;
  final String? labelId;

  @override
  Component build(BuildContext context) {
    if (operator.needsListValue) {
      if (shape.kind == ColumnShapeKind.enum_) {
        return TableEditEnumMultiSelect(
          id: id,
          enumValues: shape.enumValues,
          valueText: valueText,
          onValueTextChanged: onValueTextChanged,
          labelId: labelId,
        );
      }
      return TableEditChipInput(
        id: id,
        valueText: valueText,
        onValueTextChanged: onValueTextChanged,
        placeholder: operator == TableWhereOperator.in_ ? 'Add values…' : 'Add excluded values…',
        labelId: labelId,
      );
    }

    if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
      return TableEditSelect(
        id: id,
        shape: shape,
        value: TableEditSelect.boolValueToSelectString(boolValue),
        onChange: (v) => onBoolValueChanged(TableEditSelect.selectStringToBool(v)),
        labelId: labelId,
        placeholder: 'Choose value',
      );
    }

    if (shape.kind == ColumnShapeKind.enum_) {
      return TableEditSelect(
        id: id,
        shape: shape,
        value: valueText,
        onChange: onValueTextChanged,
        labelId: labelId,
        placeholder: 'Choose value',
      );
    }

    if (isDateTimeColumnKind(shape.kind)) {
      return TableFilterDatetimeField(
        id: id,
        valueText: valueText,
        onValueTextChanged: onValueTextChanged,
        labelId: labelId,
      );
    }

    if (shape.kind == ColumnShapeKind.integer ||
        shape.kind == ColumnShapeKind.bigInt ||
        shape.kind == ColumnShapeKind.real) {
      return TableEditNumberField(
        id: id,
        shape: shape,
        value: valueText,
        onInput: onValueTextChanged,
        labelId: labelId,
        placeholder: 'Value',
      );
    }

    if (isForeignKeyColumn(shape)) {
      return div(classes: 'table-filter-fk-value', [
        input<String>(
          id: id,
          type: .text,
          classes: ZonaiClasses.input,
          attributes: {
            if (labelId != null) 'aria-labelledby': labelId!,
            'placeholder': 'Reference id',
            'autocomplete': 'off',
          },
          value: valueText,
          onInput: onValueTextChanged,
        ),
        button(
          type: .button,
          classes: '${ZonaiClasses.btn} ${ZonaiClasses.btnGhost} table-filter-fk-browse',
          disabled: true,
          attributes: {'title': 'Browse (coming soon)'},
          [.text('Browse')],
        ),
      ]);
    }

    final attrs = Map<String, String>.from(validationAttributesForShape(shape));
    final inputType = attrs.remove('type');
    return input<String>(
      id: id,
      type: inputType == 'email' ? .email : .text,
      classes: ZonaiClasses.input,
      attributes: {
        ...attrs,
        if (labelId != null) 'aria-labelledby': labelId!,
        'placeholder': 'Value',
        'autocomplete': 'off',
      },
      value: valueText,
      onInput: onValueTextChanged,
    );
  }
}
