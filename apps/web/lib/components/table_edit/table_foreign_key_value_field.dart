import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../theme/ui_styles.dart';
import '../theme/zonai_button.dart';

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

  @override
  Component build(BuildContext context) {
    final layoutClass = switch (layout) {
      TableForeignKeyLayout.row => 'table-edit-fk-value',
      TableForeignKeyLayout.column => 'table-filter-fk-value',
    };

    return div(classes: layoutClass, [
      if (textValue.isNotEmpty)
        span(classes: 'table-edit-fk-value__chip', [.text(textValue)]),
      input<String>(
        id: id,
        type: .text,
        classes: [
          inputClass ?? ZonaiClasses.input,
          if (layout == TableForeignKeyLayout.row) 'table-edit-fk-value__input',
        ].join(' ').trim(),
        attributes: {
          if (labelId != null) 'aria-labelledby': labelId!,
          'placeholder': shape.isNullable ? 'Reference id (optional)' : 'Reference id',
          'autocomplete': 'off',
        },
        value: textValue,
        disabled: disabled,
        onInput: onTextChanged,
      ),
      ZonaiButton(
        variant: ZonaiButtonVariant.ghost,
        disabled: disabled,
        onClick: onBrowse,
        child: .text('Browse'),
      ),
    ]);
  }
}

enum TableForeignKeyLayout { row, column }
