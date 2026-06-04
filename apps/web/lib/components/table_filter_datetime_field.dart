import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../constants/theme.dart';
import '../utils/table_cell_edit.dart';
import 'app_tooltip_overlay.dart';
import 'table_edit/table_edit_datetime_field.dart';

/// Relative date preset for datetime filter values.
typedef _DatetimeFilterPreset = ({
  String label,
  String tooltip,
  DateTime Function({required bool useUtc}) toWall,
});

typedef _DatetimeFilterPresetGroup = ({String label, List<_DatetimeFilterPreset> presets});

final _presetGroups = <_DatetimeFilterPresetGroup>[
  (
    label: 'Past',
    presets: [
      (label: 'Today', tooltip: 'Start of today', toWall: _startOfToday),
      (label: '7 days ago', tooltip: 'Start of day, 7 days ago', toWall: ({required useUtc}) => _daysAgoStart(7, useUtc: useUtc)),
      (label: '30 days ago', tooltip: 'Start of day, 30 days ago', toWall: ({required useUtc}) => _daysAgoStart(30, useUtc: useUtc)),
      (label: '90 days ago', tooltip: 'Start of day, 90 days ago', toWall: ({required useUtc}) => _daysAgoStart(90, useUtc: useUtc)),
    ],
  ),
  (
    label: 'Future',
    presets: [
      (label: 'Now', tooltip: 'Current date and time', toWall: ({required useUtc}) => useUtc ? DateTime.now().toUtc() : DateTime.now()),
      (label: 'in 7 days', tooltip: 'Start of day, 7 days from today', toWall: ({required useUtc}) => _daysAheadStart(7, useUtc: useUtc)),
      (label: 'in 30 days', tooltip: 'Start of day, 30 days from today', toWall: ({required useUtc}) => _daysAheadStart(30, useUtc: useUtc)),
      (label: 'in 90 days', tooltip: 'Start of day, 90 days from today', toWall: ({required useUtc}) => _daysAheadStart(90, useUtc: useUtc)),
    ],
  ),
];

DateTime _startOfToday({required bool useUtc}) {
  if (useUtc) {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _daysAgoStart(int days, {required bool useUtc}) => _startOfToday(useUtc: useUtc).subtract(Duration(days: days));

DateTime _daysAheadStart(int days, {required bool useUtc}) => _startOfToday(useUtc: useUtc).add(Duration(days: days));

bool _presetMatches(String valueText, DateTime presetWall, {required bool useUtc}) {
  final selected = filterDateTimeTextToWall(valueText, useUtc: useUtc);
  if (selected == null) return false;
  return wallDateTimeToFilterText(selected, useUtc: useUtc) ==
      wallDateTimeToFilterText(presetWall, useUtc: useUtc);
}

/// Datetime filter value: timezone, grouped quick presets, and a compact custom picker.
class TableFilterDatetimeField extends StatelessComponent {
  const TableFilterDatetimeField({
    super.key,
    required this.id,
    required this.valueText,
    required this.onValueTextChanged,
    required this.dateTimeUseUtc,
    required this.onDateTimeUseUtcChanged,
    this.labelId,
  });

  final String id;
  final String valueText;
  final void Function(String valueText) onValueTextChanged;
  final bool dateTimeUseUtc;
  final void Function(bool useUtc) onDateTimeUseUtcChanged;
  final String? labelId;

  @override
  Component build(BuildContext context) {
    final useUtc = dateTimeUseUtc;
    return div(
      id: id,
      classes: 'table-filter-datetime',
      attributes: {
        if (labelId != null) 'aria-labelledby': labelId!,
      },
      [
        div(
          classes: 'table-search-operators table-filter-datetime__timezone',
          attributes: {'role': 'group', 'aria-label': 'Timezone'},
          [
            _timezoneButton(
              context,
              label: 'Local',
              tooltip: 'Presets and picker use your local timezone',
              selected: !useUtc,
              onSelect: () => onDateTimeUseUtcChanged(false),
            ),
            _timezoneButton(
              context,
              label: 'UTC',
              tooltip: 'Presets and picker use UTC',
              selected: useUtc,
              onSelect: () => onDateTimeUseUtcChanged(true),
            ),
          ],
        ),
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
                    useUtc: useUtc,
                    selected: _presetMatches(valueText, preset.toWall(useUtc: useUtc), useUtc: useUtc),
                    onSelect: () => onValueTextChanged(
                      wallDateTimeToFilterText(preset.toWall(useUtc: useUtc), useUtc: useUtc),
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
            useUtc: useUtc,
            compact: true,
            placeholder: 'Custom date…',
          ),
        ]),
      ],
    );
  }

  Component _timezoneButton(
    BuildContext context, {
    required String label,
    required String tooltip,
    required bool selected,
    required void Function() onSelect,
  }) {
    return button(
      type: .button,
      classes: [
        'table-search-op',
        'table-filter-datetime__timezone-btn',
        if (selected) 'table-search-op--active',
      ].join(' '),
      attributes: {'aria-pressed': selected ? 'true' : 'false'},
      events: appTooltipEvents(context, text: tooltip),
      onClick: onSelect,
      [.text(label)],
    );
  }

  Component _presetButton(
    BuildContext context, {
    required _DatetimeFilterPreset preset,
    required bool useUtc,
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
  css('.table-filter-datetime__timezone').styles(margin: .zero),
  css('.table-filter-datetime__timezone-btn').styles(
    fontSize: 0.8125.rem,
    fontWeight: .w600,
    padding: .symmetric(horizontal: 12.px, vertical: 5.px),
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
