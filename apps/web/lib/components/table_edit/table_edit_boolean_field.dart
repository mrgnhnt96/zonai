import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme/zonai_button.dart';

/// Checkbox editor for boolean columns (checked = true).
class TableEditBooleanField extends StatelessComponent {
  const TableEditBooleanField({
    super.key,
    required this.id,
    required this.value,
    required this.onChanged,
    this.labelId,
    this.allowNullable = false,
    this.disabled = false,
  });

  final String id;
  final bool? value;
  final void Function(bool? value) onChanged;
  final String? labelId;
  final bool allowNullable;
  final bool disabled;

  @override
  Component build(BuildContext context) {
    final checked = value == true;

    return div(classes: 'table-edit-boolean', [
      label(
        classes: 'table-edit-boolean__label',
        [
          input<bool>(
            id: id,
            type: .checkbox,
            classes: 'table-edit-boolean__checkbox',
            attributes: {
              if (labelId != null) 'aria-labelledby': labelId!,
            },
            checked: checked,
            disabled: disabled,
            onChange: (v) {
              if (v) {
                onChanged(true);
              } else if (allowNullable) {
                onChanged(null);
              } else {
                onChanged(false);
              }
            },
          ),
          span(classes: 'table-edit-boolean__hint', [.text('True when checked')]),
        ],
      ),
      if (allowNullable && value != null)
        ZonaiButton(
          variant: ZonaiButtonVariant.ghost,
          disabled: disabled,
          onClick: () => onChanged(null),
          child: .text('Clear'),
        ),
    ]);
  }
}
