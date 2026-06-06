import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../theme/ui_styles.dart';
import '../theme/zonai_button.dart';
import '../theme/zonai_tag.dart';

/// Shared foreign-key value row: optional chip, id input, and Browse button.
class TableForeignKeyValueField extends StatelessComponent {
  const TableForeignKeyValueField({
    super.key,
    required this.id,
    required this.shape,
    required this.textValue,
    required this.onTextChanged,
    required this.onBrowse,
    this.labelId,
    this.disabled = false,
    this.layout = TableForeignKeyLayout.row,
    this.inputClass,
    this.displayLabel,
    this.validationError,
    this.validationLoading = false,
  });

  final String id;
  final ColumnShape shape;
  final String textValue;
  final void Function(String value) onTextChanged;
  final VoidCallback onBrowse;
  final String? labelId;
  final bool disabled;
  final TableForeignKeyLayout layout;
  final String? inputClass;
  final String? displayLabel;
  final String? validationError;
  final bool validationLoading;

  @override
  Component build(BuildContext context) {
    final layoutClass = switch (layout) {
      TableForeignKeyLayout.row => 'table-edit-fk-value',
      TableForeignKeyLayout.column => 'table-filter-fk-value',
    };

    final chipLabel = displayLabel ?? (textValue.isNotEmpty ? textValue : null);
    final inputClasses = [
      inputClass ?? ZonaiClasses.input,
      if (layout == TableForeignKeyLayout.row) 'table-edit-fk-value__input',
      if (validationError != null) 'table-edit-fk-value__input--invalid',
    ].join(' ').trim();

    // TODO(open-referenced-row-tab): When [textValue] is set and validation is valid,
    // add a ghost icon button that opens the referenced row in a new browser tab.

    return div(classes: layoutClass, [
      if (chipLabel != null) ZonaiTag(label: chipLabel, monospace: displayLabel == null),
      input<String>(
        id: id,
        type: .text,
        classes: inputClasses,
        attributes: {
          if (labelId != null) 'aria-labelledby': labelId!,
          if (validationError != null) 'aria-invalid': 'true',
          if (validationError != null) 'aria-describedby': '$id-error',
          'placeholder': shape.isNullable ? 'Reference id (optional)' : 'Reference id',
          'autocomplete': 'off',
        },
        value: textValue,
        disabled: disabled,
        onInput: onTextChanged,
      ),
      ZonaiButton(variant: ZonaiButtonVariant.ghost, disabled: disabled, onClick: onBrowse, child: .text('Browse')),
      if (validationLoading) span(classes: 'table-edit-fk-value__hint', [.text('Checking…')]),
      if (validationError != null) p(id: '$id-error', classes: 'table-edit-fk-value__error', [.text(validationError!)]),
    ]);
  }
}

enum TableForeignKeyLayout { row, column }
