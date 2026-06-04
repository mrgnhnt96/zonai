import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';

/// Decimal text input for [ColumnShapeKind.bigInt] (avoids HTML number precision limits).
class TableEditBigIntField extends StatelessComponent {
  const TableEditBigIntField({
    super.key,
    required this.id,
    required this.shape,
    required this.value,
    required this.onInput,
    this.labelId,
    this.placeholder,
    this.disabled = false,
    this.inputClass,
  });

  final String id;
  final ColumnShape shape;
  final String value;
  final void Function(String value) onInput;
  final String? labelId;
  final String? placeholder;
  final bool disabled;
  final String? inputClass;

  void _emitText(String text) => onInput(filterBigIntDecimalInput(text));

  @override
  Component build(BuildContext context) {
    return input<String>(
      id: id,
      type: .text,
      classes: inputClass ?? ZonaiClasses.input,
      attributes: {
        'inputmode': 'numeric',
        'pattern': r'-?\d*',
        if (labelId != null) 'aria-labelledby': labelId!,
        if (placeholder != null) 'placeholder': placeholder!,
        'autocomplete': 'off',
      },
      value: value,
      disabled: disabled,
      onInput: _emitText,
      onChange: _emitText,
    );
  }
}
