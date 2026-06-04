import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/table_cell_edit.dart';
import '../utils/table_where_operators.dart';
import 'table_edit/table_edit_chip_input.dart';
import 'table_edit/table_edit_enum_multi_select.dart';
import 'table_filter_datetime_field.dart';
import 'table_edit/table_edit_number_field.dart';
import 'table_edit/foreign_key_picker_dialog.dart';
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
    this.dateTimeUseUtc = false,
    this.onDateTimeUseUtcChanged,
    this.labelId,
  });

  final String id;
  final ColumnShape shape;
  final TableWhereOperator operator;
  final String valueText;
  final bool boolValue;
  final void Function(String valueText) onValueTextChanged;
  final void Function(bool boolValue) onBoolValueChanged;
  final bool dateTimeUseUtc;
  final void Function(bool useUtc)? onDateTimeUseUtcChanged;
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
        dateTimeUseUtc: dateTimeUseUtc,
        onDateTimeUseUtcChanged: onDateTimeUseUtcChanged ?? (_) {},
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

    if (isForeignKeyColumn(shape) && shape.foreignKey != null) {
      return _TableFilterFkValueField(
        id: id,
        shape: shape,
        valueText: valueText,
        onValueTextChanged: onValueTextChanged,
        labelId: labelId,
      );
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

class _TableFilterFkValueField extends StatefulComponent {
  const _TableFilterFkValueField({
    required this.id,
    required this.shape,
    required this.valueText,
    required this.onValueTextChanged,
    this.labelId,
  });

  final String id;
  final ColumnShape shape;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final String? labelId;

  @override
  State<_TableFilterFkValueField> createState() => _TableFilterFkValueFieldState();
}

class _TableFilterFkValueFieldState extends State<_TableFilterFkValueField> {
  var _pickerOpen = false;

  @override
  Component build(BuildContext context) {
    final fk = component.shape.foreignKey!;

    return Component.fragment([
      div(classes: 'table-filter-fk-value', [
        input<String>(
          id: component.id,
          type: .text,
          classes: ZonaiClasses.input,
          attributes: {
            if (component.labelId != null) 'aria-labelledby': component.labelId!,
            'placeholder': 'Reference id',
            'autocomplete': 'off',
          },
          value: component.valueText,
          onInput: component.onValueTextChanged,
        ),
        button(
          type: .button,
          classes: '${ZonaiClasses.btn} ${ZonaiClasses.btnGhost} table-filter-fk-browse',
          onClick: () => setState(() => _pickerOpen = true),
          [.text('Browse')],
        ),
      ]),
      if (_pickerOpen)
        ForeignKeyPickerDialog(
          foreignKey: fk,
          selectedId: component.valueText.isEmpty ? null : component.valueText,
          onSelect: (id) {
            component.onValueTextChanged(id ?? '');
            setState(() => _pickerOpen = false);
          },
          onClose: () => setState(() => _pickerOpen = false),
        ),
    ]);
  }
}
