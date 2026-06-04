import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../constants/theme.dart';
import '../utils/table_cell_edit.dart';
import 'app_tooltip_overlay.dart';
import 'table_edit/table_edit_datetime_field.dart';

/// Relative date preset for datetime filter values.
typedef _DatetimeFilterPreset = ({String label, String tooltip, DateTime Function() toLocal});

typedef _DatetimeFilterPresetGroup = ({String label, List<_DatetimeFilterPreset> presets});

final _presetGroups = <_DatetimeFilterPresetGroup>[
  (
    label: 'Past',
    presets: [
      (label: 'Today', tooltip: 'Start of today', toLocal: _startOfToday),
      (label: '7 days ago', tooltip: 'Start of day, 7 days ago', toLocal: () => _daysAgoStart(7)),
      (label: '30 days ago', tooltip: 'Start of day, 30 days ago', toLocal: () => _daysAgoStart(30)),
      (label: '90 days ago', tooltip: 'Start of day, 90 days ago', toLocal: () => _daysAgoStart(90)),
    ],
  ),
  (
    label: 'Future',
    presets: [
      (label: 'Now', tooltip: 'Current date and time', toLocal: DateTime.now),
      (label: 'in 7 days', tooltip: 'Start of day, 7 days from today', toLocal: () => _daysAheadStart(7)),
      (label: 'in 30 days', tooltip: 'Start of day, 30 days from today', toLocal: () => _daysAheadStart(30)),
      (label: 'in 90 days', tooltip: 'Start of day, 90 days from today', toLocal: () => _daysAheadStart(90)),
    ],
  ),
];

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _daysAgoStart(int days) => _startOfToday().subtract(Duration(days: days));

DateTime _daysAheadStart(int days) => _startOfToday().add(Duration(days: days));

bool _presetMatches(String valueText, DateTime presetLocal) {
  final selected = filterDateTimeTextToLocal(valueText);
  if (selected == null) return false;
  return localWallDateTimeToFilterText(selected) == localWallDateTimeToFilterText(presetLocal);
}

/// Datetime filter value: grouped quick presets plus a compact custom picker.
class TableFilterDatetimeField extends StatelessComponent {
  const TableFilterDatetimeField({
    super.key,
    required this.id,
    required this.valueText,
    required this.onValueTextChanged,
    this.labelId,
  });

  final String id;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final String? labelId;

  @override
  Component build(BuildContext context) {
    return div(
      id: id,
      classes: 'table-filter-datetime',
      attributes: {
        if (labelId != null) 'aria-labelledby': labelId!,
      },
      [
        for (final group in _presetGroups)
          div(classes: 'table-filter-datetime__group', [
            span(classes: 'table-filter-datetime__group-label', [.text(group.label)]),
            div(
              classes: 'table-search-operators table-filter-datetime__presets',
              attributes: {'role': 'group', 'aria-label': '${group.label} date presets'},
              [
                for (final preset in group.presets)
                  _presetButton(
                    context,
                    preset: preset,
                    selected: _presetMatches(valueText, preset.toLocal()),
                    onSelect: () => onValueTextChanged(
                      localWallDateTimeToFilterText(preset.toLocal()),
                    ),
                  ),
              ],
            ),
          ]),
        div(classes: 'table-filter-datetime__picker', [
          TableEditDatetimeField(
            id: '$id-picker',
            valueText: valueText,
            onValueTextChanged: onValueTextChanged,
            compact: true,
            placeholder: 'Custom date…',
          ),
        ]),
      ],
    );
  }

  Component _presetButton(
    BuildContext context, {
    required _DatetimeFilterPreset preset,
    required bool selected,
    required void Function() onSelect,
  }) {
    return button(
      type: .button,
      classes: [
        'table-search-op',
        'table-filter-datetime__preset',
        if (selected) 'table-search-op--active',
      ].join(' '),
      attributes: {'aria-pressed': selected ? 'true' : 'false'},
      events: appTooltipEvents(context, text: preset.tooltip),
      onClick: onSelect,
      [.text(preset.label)],
    );
  }
}

/// Layout for [TableFilterDatetimeField] (search panel).
@css
List<StyleRule> tableFilterDatetimeStyles = [
  css('.table-filter-datetime').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(10.px),
    alignItems: .start,
    width: 100.percent,
  ),
  css('.table-filter-datetime__group').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(6.px),
    width: 100.percent,
  ),
  css('.table-filter-datetime__group-label').styles(
    fontSize: 0.6875.rem,
    fontWeight: .w600,
    color: mutedColor,
    letterSpacing: 0.04.rem,
    raw: const {'text-transform': 'uppercase'},
  ),
  css('.table-filter-datetime__presets').styles(margin: .zero),
  css('.table-filter-datetime__preset').styles(
    fontSize: 0.8125.rem,
    padding: .symmetric(horizontal: 10.px, vertical: 5.px),
  ),
  css('.table-filter-datetime__picker').styles(
    width: 100.percent,
    padding: .only(top: 14.px),
    margin: .only(top: 2.px),
    border: .only(top: BorderSide.solid(color: borderColor, width: 1.px)),
  ),
  css('.table-filter-datetime__picker .table-edit-datetime--compact').styles(
    width: .auto,
    maxWidth: 280.px,
  ),
];
