import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';

class TableEditNumberField extends StatelessComponent {
  const TableEditNumberField({
    super.key,
    required this.id,
    required this.shape,
    required this.value,
    required this.onInput,
    this.labelId,
    this.placeholder,
  });

  final String id;
  final ColumnShape shape;
  final String value;
  final void Function(String value) onInput;
  final String? labelId;
  final String? placeholder;

  @override
  Component build(BuildContext context) {
    final attrs = <String, String>{
      ...validationAttributesForShape(shape),
      if (labelId != null) 'aria-labelledby': labelId!,
      if (placeholder != null) 'placeholder': placeholder!,
      'autocomplete': 'off',
    };

    return input<num>(
      id: id,
      type: .number,
      classes: ZonaiClasses.input,
      attributes: attrs,
      value: value,
      onInput: _emitText,
      onChange: _emitText,
    );
  }

  void _emitText(num raw) => onInput(_numberInputToText(raw, shape));

  /// Jaspr number inputs emit [num] (see `events.dart`); wire text stays [String].
  String _numberInputToText(num raw, ColumnShape shape) {
    if (raw.isNaN) return '';
    return switch (shape.kind) {
      ColumnShapeKind.integer => raw.toInt().toString(),
      ColumnShapeKind.bigInt => raw.toInt().toString(),
      _ => raw.toString(),
    };
  }
}
