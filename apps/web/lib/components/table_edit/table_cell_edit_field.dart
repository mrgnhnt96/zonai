import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';
import 'foreign_key_picker_dialog.dart';
import 'table_value_editor.dart';

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

    final editor = TableValueEditor(
      id: component.id,
      shape: shape,
      value: component.value,
      textValue: component.textValue,
      disabled: component.disabled,
      labelId: component.labelId,
      onTextChanged: component.onTextChanged,
      onDraftChanged: component.onDraftChanged,
      onBrowse: isForeignKeyColumn(shape) ? _openFkPicker : null,
      inputClass: ZonaiClasses.input,
      allowNullableEnum: shape.isNullable,
    );

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
}
