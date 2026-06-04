import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/table_cell_edit.dart';
import '../utils/table_where_operators.dart';
import 'table_edit/foreign_key_picker_dialog.dart';
import 'table_edit/table_foreign_key_value_field.dart';
import 'table_edit/table_value_editor.dart';
import 'table_filter_datetime_field.dart';

/// Value editor for one filter condition row (type-aware).
class TableFilterValueField extends StatefulComponent {
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
  State<TableFilterValueField> createState() => _TableFilterValueFieldState();
}

class _TableFilterValueFieldState extends State<TableFilterValueField> {
  var _fkPickerOpen = false;

  @override
  Component build(BuildContext context) {
    final shape = component.shape;
    final op = component.operator;

    if (op.needsListValue) {
      return TableValueEditor(
        id: component.id,
        shape: shape,
        textValue: component.valueText,
        labelId: component.labelId,
        onTextChanged: component.onValueTextChanged,
        enumMultiSelect: shape.kind == ColumnShapeKind.enum_,
        chipPlaceholder: op == TableWhereOperator.in_ ? 'Add values…' : 'Add excluded values…',
      );
    }

    if (isDateTimeColumnKind(shape.kind)) {
      return TableFilterDatetimeField(
        id: component.id,
        valueText: component.valueText,
        onValueTextChanged: component.onValueTextChanged,
        dateTimeUseUtc: component.dateTimeUseUtc,
        onDateTimeUseUtcChanged: component.onDateTimeUseUtcChanged ?? (_) {},
        labelId: component.labelId,
      );
    }

    if (isForeignKeyColumn(shape) && shape.foreignKey != null) {
      return Component.fragment([
        TableValueEditor(
          id: component.id,
          shape: shape,
          textValue: component.valueText,
          labelId: component.labelId,
          onTextChanged: component.onValueTextChanged,
          onBrowse: () => setState(() => _fkPickerOpen = true),
          fkLayout: TableForeignKeyLayout.column,
        ),
        if (_fkPickerOpen)
          ForeignKeyPickerDialog(
            foreignKey: shape.foreignKey!,
            selectedId: component.valueText.isEmpty ? null : component.valueText,
            onSelect: (id) {
              component.onValueTextChanged(id ?? '');
              setState(() => _fkPickerOpen = false);
            },
            onClose: () => setState(() => _fkPickerOpen = false),
          ),
      ]);
    }

    return TableValueEditor(
      id: component.id,
      shape: shape,
      textValue: component.valueText,
      boolValue: component.boolValue,
      labelId: component.labelId,
      onTextChanged: component.onValueTextChanged,
      onBoolChanged: (v) => component.onBoolValueChanged(v ?? false),
      chipPlaceholder: 'Value',
    );
  }
}
