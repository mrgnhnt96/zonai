import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';

/// JSON textarea for map and blob column editing.
class TableEditJsonField extends StatelessComponent {
  const TableEditJsonField({
    super.key,
    required this.id,
    required this.value,
    required this.onInput,
    this.labelId,
    this.placeholder,
    this.disabled = false,
    this.inputClass,
    this.validateAsMap = false,
    this.allowEmpty = false,
  });

  final String id;
  final String value;
  final void Function(String value) onInput;
  final String? labelId;
  final String? placeholder;
  final bool disabled;
  final String? inputClass;
  final bool validateAsMap;
  final bool allowEmpty;

  @override
  Component build(BuildContext context) {
    final validationError = validateAsMap && value.trim().isNotEmpty
        ? validateMapEditText(value, allowEmpty: allowEmpty)
        : null;

    return div(classes: 'table-edit-json-field', [
      textarea(
        [.text(value)],
        id: id,
        classes: inputClass ?? ZonaiClasses.input,
        placeholder: placeholder,
        rows: 4,
        spellCheck: SpellCheck.isFalse,
        disabled: disabled,
        attributes: {
          if (labelId != null) 'aria-labelledby': labelId!,
          if (validationError != null) 'aria-invalid': 'true',
          if (validationError != null) 'aria-describedby': '$id-error',
        },
        onInput: onInput,
      ),
      if (validationError != null)
        p(id: '$id-error', classes: 'table-edit-json-field__error', [.text(validationError)]),
    ]);
  }
}
