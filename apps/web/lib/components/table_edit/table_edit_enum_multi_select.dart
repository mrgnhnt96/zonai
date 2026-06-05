import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/button_sizes.dart';
import '../../constants/theme.dart';
import '../../utils/table_cell_edit.dart';
import '../../constants/spacing.dart';

/// Toggle chips for enum `in` / `not in` filter values.
class TableEditEnumMultiSelect extends StatelessComponent {
  const TableEditEnumMultiSelect({
    super.key,
    required this.id,
    required this.enumValues,
    required this.valueText,
    required this.onValueTextChanged,
    this.labelId,
  });

  final String id;
  final List<String> enumValues;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final String? labelId;

  @override
  Component build(BuildContext context) {
    final selected = parseCommaSeparatedList(valueText);

    if (enumValues.isEmpty) {
      return div(
        id: id,
        classes: 'table-edit-enum-values table-edit-enum-values--empty',
        attributes: {
          if (labelId != null) 'aria-labelledby': labelId!,
        },
        [.text('No values defined for this column')],
      );
    }

    return div(
      id: id,
      classes: 'table-search-operators table-edit-enum-values',
      attributes: {
        'role': 'group',
        if (labelId != null) 'aria-labelledby': labelId!,
      },
      [
        for (final value in enumValues)
          button(
            type: .button,
            classes: [
              'table-search-op',
              'table-edit-enum-value',
              if (selected.contains(value)) 'table-edit-enum-value--selected',
            ].join(' '),
            attributes: {'aria-pressed': selected.contains(value) ? 'true' : 'false'},
            onClick: () => _toggle(value, selected),
            [.text(value)],
          ),
      ],
    );
  }

  void _toggle(String value, List<String> selected) {
    final next = [...selected];
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    onValueTextChanged(joinCommaSeparatedList(next));
  }
}

/// Enum value chip overrides (base layout uses `.table-search-operators` / `.table-search-op`).
@css
List<StyleRule> tableEditEnumMultiSelectStyles = [
  css('.table-search-op.table-edit-enum-value').styles(
    padding: .symmetric(
      horizontal: ZonaiButtonSizes.textPaddingHorizontal(ZonaiButtonSize.sm),
      vertical: ZonaiSpacing.s2_5,
    ),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.sm),
    radius: .all(Radius.circular(100.px)),
    raw: const {
      'line-height': '1.3',
      'transition': 'background-color 0.15s ease, border-color 0.15s ease, color 0.15s ease',
    },
  ),
  css('.table-search-op.table-edit-enum-value--selected').styles(
    backgroundColor: primaryColor,
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    color: onPrimaryColor,
    fontWeight: .w600,
  ),
  css('.table-search-op.table-edit-enum-value--selected:hover').styles(
    backgroundColor: primaryHoverColor,
    border: .all(color: primaryHoverColor, width: 1.px, style: .solid),
    color: onPrimaryColor,
  ),
];
