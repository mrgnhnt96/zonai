import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';
import 'foreign_key_picker_dialog.dart';
import 'table_edit_chip_input.dart';
import 'table_edit_datetime_field.dart';
import 'table_edit_enum_multi_select.dart';
import 'table_edit_number_field.dart';
import 'table_edit_select.dart';

/// Type-aware value editor for row detail edit mode.
class TableCellEditField extends StatefulComponent {
  const TableCellEditField({
    super.key,
    required this.id,
    required this.shape,
    required this.value,
    required this.textValue,
    required this.disabled,
    required this.onTextChanged,
    required this.onDraftChanged,
    this.labelId,
  });

  final String id;
  final ColumnShape shape;
  final Object? value;
  final String textValue;
  final bool disabled;
  final void Function(String text) onTextChanged;
  final void Function(Object? value) onDraftChanged;
  final String? labelId;

  @override
  State<TableCellEditField> createState() => _TableCellEditFieldState();
}

class _TableCellEditFieldState extends State<TableCellEditField> {
  var _fkPickerOpen = false;

  void _openFkPicker() {
    if (component.disabled || component.shape.foreignKey == null) return;
    setState(() => _fkPickerOpen = true);
  }

  void _closeFkPicker() => setState(() => _fkPickerOpen = false);

  @override
  Component build(BuildContext context) {
    final shape = component.shape;
    final id = component.id;
    final labelId = component.labelId;

    final editor = switch (shape.kind) {
      ColumnShapeKind.boolean || ColumnShapeKind.isVerified => TableEditSelect(
        id: id,
        shape: shape,
        value: _boolSelectValue(component.value),
        onChange: (v) {
          if (shape.isNullable && v.isEmpty) {
            component.onDraftChanged(null);
            return;
          }
          component.onDraftChanged(TableEditSelect.selectStringToBool(v));
        },
        labelId: labelId,
        disabled: component.disabled,
        allowNullable: shape.isNullable,
        placeholder: shape.isNullable ? '—' : 'Choose value',
      ),
      ColumnShapeKind.enum_ => TableEditSelect(
        id: id,
        shape: shape,
        value: component.textValue,
        onChange: component.onTextChanged,
        labelId: labelId,
        disabled: component.disabled,
        allowNullable: shape.isNullable,
        placeholder: shape.isNullable ? '—' : 'Choose value',
      ),
      ColumnShapeKind.dateTime => TableEditDatetimeField(
        id: id,
        valueText: component.textValue,
        onValueTextChanged: component.onTextChanged,
        labelId: labelId,
        placeholder: 'Choose date and time',
      ),
      ColumnShapeKind.integer || ColumnShapeKind.bigInt || ColumnShapeKind.real => TableEditNumberField(
        id: id,
        shape: shape,
        value: component.textValue,
        onInput: component.onTextChanged,
        labelId: labelId,
        placeholder: shape.isNullable ? 'Leave empty for null' : 'Value',
      ),
      ColumnShapeKind.list => TableEditChipInput(
        id: id,
        valueText: joinCommaSeparatedList(cellValueAsStringList(component.value)),
        onValueTextChanged: (text) {
          component.onDraftChanged(parseCommaSeparatedList(text));
        },
        placeholder: 'Add value…',
        labelId: labelId,
      ),
      ColumnShapeKind.enumList => TableEditEnumMultiSelect(
        id: id,
        enumValues: shape.enumValues,
        valueText: joinCommaSeparatedList(cellValueAsStringList(component.value, shape.enumValues)),
        onValueTextChanged: (text) {
          component.onDraftChanged(parseCommaSeparatedList(text));
        },
        labelId: labelId,
      ),
      _ when isForeignKeyColumn(shape) => _ForeignKeyValueEditor(
        id: id,
        shape: shape,
        textValue: component.textValue,
        disabled: component.disabled,
        labelId: labelId,
        onTextChanged: component.onTextChanged,
        onBrowse: _openFkPicker,
      ),
      _ => _plainTextEditor(shape, id, labelId),
    };

    if (!_fkPickerOpen || shape.foreignKey == null) {
      return editor;
    }

    return Component.fragment([
      editor,
      ForeignKeyPickerDialog(
        foreignKey: shape.foreignKey!,
        selectedId: component.textValue.isEmpty ? null : component.textValue,
        onSelect: (id) {
          component.onTextChanged(id ?? '');
          _closeFkPicker();
        },
        onClose: _closeFkPicker,
      ),
    ]);
  }

  String _boolSelectValue(Object? value) {
    if (value == null) return '';
    return TableEditSelect.boolValueToSelectString(cellEditValueAsBool(value));
  }

  Component _plainTextEditor(ColumnShape shape, String id, String? labelId) {
    final attrs = Map<String, String>.from(validationAttributesForShape(shape));
    final inputType = attrs.remove('type');
    return input<String>(
      id: id,
      type: inputType == 'email' ? .email : .text,
      classes: 'table-row-detail-edit-input',
      attributes: {
        ...attrs,
        if (labelId != null) 'aria-labelledby': labelId!,
        if (shape.isNullable) 'placeholder': 'Leave empty for null',
        'autocomplete': 'off',
      },
      value: component.textValue,
      disabled: component.disabled,
      onInput: component.onTextChanged,
    );
  }
}

class _ForeignKeyValueEditor extends StatelessComponent {
  const _ForeignKeyValueEditor({
    required this.id,
    required this.shape,
    required this.textValue,
    required this.disabled,
    required this.labelId,
    required this.onTextChanged,
    required this.onBrowse,
  });

  final String id;
  final ColumnShape shape;
  final String textValue;
  final bool disabled;
  final String? labelId;
  final void Function(String value) onTextChanged;
  final VoidCallback onBrowse;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-edit-fk-value', [
      if (textValue.isNotEmpty)
        span(classes: 'table-edit-fk-value__chip', [.text(textValue)]),
      input<String>(
        id: id,
        type: .text,
        classes: 'table-row-detail-edit-input table-edit-fk-value__input',
        attributes: {
          if (labelId != null) 'aria-labelledby': labelId!,
          'placeholder': shape.isNullable ? 'Reference id (optional)' : 'Reference id',
          'autocomplete': 'off',
        },
        value: textValue,
        disabled: disabled,
        onInput: onTextChanged,
      ),
      button(
        type: .button,
        classes: '${ZonaiClasses.btn} ${ZonaiClasses.btnGhost} table-edit-fk-browse',
        disabled: disabled,
        onClick: onBrowse,
        [.text('Browse')],
      ),
    ]);
  }
}
