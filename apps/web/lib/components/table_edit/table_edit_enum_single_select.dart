import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Single-select chip group for enum column values (radio behavior).
class TableEditEnumSingleSelect extends StatelessComponent {
  const TableEditEnumSingleSelect({
    super.key,
    required this.id,
    required this.enumValues,
    required this.value,
    required this.onChange,
    this.labelId,
    this.allowNullable = false,
    this.disabled = false,
  });

  final String id;
  final List<String> enumValues;
  final String value;
  final void Function(String value) onChange;
  final String? labelId;
  final bool allowNullable;
  final bool disabled;

  @override
  Component build(BuildContext context) {
    if (enumValues.isEmpty) {
      return div(
        id: id,
        classes: 'table-edit-enum-values table-edit-enum-values--empty',
        attributes: {if (labelId != null) 'aria-labelledby': labelId!},
        [.text('No values defined for this column')],
      );
    }

    return div(
      id: id,
      classes: 'table-search-operators table-edit-enum-values',
      attributes: {'role': 'radiogroup', if (labelId != null) 'aria-labelledby': labelId!},
      [
        if (allowNullable)
          button(
            type: .button,
            classes: [
              'table-search-op',
              'table-edit-enum-value',
              if (value.isEmpty) 'table-edit-enum-value--selected',
            ].join(' '),
            attributes: {
              'aria-checked': value.isEmpty ? 'true' : 'false',
              'role': 'radio',
              if (disabled) 'disabled': 'true',
            },
            onClick: disabled ? null : () => onChange(''),
            [.text('—')],
          ),
        for (final enumValue in enumValues)
          button(
            type: .button,
            classes: [
              'table-search-op',
              'table-edit-enum-value',
              if (value == enumValue) 'table-edit-enum-value--selected',
            ].join(' '),
            attributes: {
              'aria-checked': value == enumValue ? 'true' : 'false',
              'role': 'radio',
              if (disabled) 'disabled': 'true',
            },
            onClick: disabled ? null : () => onChange(enumValue),
            [.text(enumValue)],
          ),
      ],
    );
  }
}
