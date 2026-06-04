import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/table_filter_provider.dart';
import '../providers/table_rows_provider.dart';
import '../utils/table_where_build.dart';
import '../utils/table_where_operators.dart';
import 'app_tooltip_overlay.dart';
import 'table_filter_value_field.dart';
import 'theme/theme_components.dart';

/// Search toggle for the table header (opens side panel).
class TableSearchToggle extends StatelessComponent {
  const TableSearchToggle({super.key});

  @override
  Component build(BuildContext context) {
    final filter = context.watch(tableFilterProvider);
    final notifier = context.read(tableFilterProvider.notifier);

    return button(
      type: .button,
      classes: [
        'table-search-toggle',
        if (filter.panelOpen) 'table-search-toggle--open',
        if (filter.hasAppliedFilter) 'table-search-toggle--active',
      ].join(' '),
      attributes: {
        'aria-label': filter.hasAppliedFilter ? 'Edit search filter' : 'Search table',
        'aria-expanded': filter.panelOpen ? 'true' : 'false',
      },
      events: appTooltipEvents(
        context,
        text: filter.hasAppliedFilter ? 'Filter active — click to edit' : 'Search / filter rows',
      ),
      onClick: () {
        if (filter.panelOpen) {
          notifier.closePanel();
        } else if (filter.hasAppliedFilter) {
          notifier.openForEdit();
        } else {
          notifier.openPanel();
        }
      },
      [searchIcon()],
    );
  }
}

/// Filter builder body (rendered inside [TableSearchSidePanel]).
class TableSearchPanel extends StatelessComponent {
  const TableSearchPanel({
    required this.columnShapes,
    required this.state,
    super.key,
  });

  final List<ColumnShape> columnShapes;
  final TableFilterState state;

  @override
  Component build(BuildContext context) {
    final notifier = context.read(tableFilterProvider.notifier);
    final showCombine = state.draftRows.length > 1;
    final columnOptions = [
      for (final shape in columnShapes)
        ZonaiSelectOption(value: shape.name, label: columnShapeHeaderLabel(shape)),
    ];

    return div(classes: 'table-search-panel-body', [
      if (showCombine) _CombineControl(combine: state.combine, onSelect: notifier.setCombine),
      div(classes: 'table-search-conditions', [
        for (var i = 0; i < state.draftRows.length; i++)
          _FilterRow(
            index: i,
            row: state.draftRows[i],
            columnShapes: columnShapes,
            columnOptions: columnOptions,
            canRemove: state.draftRows.length > 1,
            onUpdate: (row) => notifier.updateRow(i, row),
            onRemove: () => notifier.removeRow(i),
          ),
      ]),
      div(classes: 'table-search-panel-footer', [
        button(
          type: .button,
          classes: '${ZonaiClasses.btn} ${ZonaiClasses.btnGhost} table-search-add-btn',
          onClick: notifier.addRow,
          [.text('+ Add filter')],
        ),
        div(classes: 'table-search-panel-actions-primary', [
          ZonaiButton(
            variant: ZonaiButtonVariant.secondary,
            onClick: notifier.clear,
            child: const .text('Clear'),
          ),
          ZonaiButton(
            onClick: () {
              if (notifier.apply()) {
                notifier.closePanel();
              }
            },
            child: const .text('Apply'),
          ),
        ]),
      ]),
    ]);
  }
}

class _CombineControl extends StatelessComponent {
  const _CombineControl({required this.combine, required this.onSelect});

  final FilterCombine combine;
  final void Function(FilterCombine) onSelect;

  @override
  Component build(BuildContext context) {
    return div(classes: 'table-search-combine', [
      span(classes: 'table-search-combine-label', [.text('Match')]),
      _segmentButton(
        context,
        label: 'AND',
        selected: combine == FilterCombine.and,
        tooltip: 'All conditions must match',
        onClick: () => onSelect(FilterCombine.and),
      ),
      _segmentButton(
        context,
        label: 'OR',
        selected: combine == FilterCombine.or,
        tooltip: 'Any condition can match',
        onClick: () => onSelect(FilterCombine.or),
      ),
    ]);
  }

  Component _segmentButton(
    BuildContext context, {
    required String label,
    required bool selected,
    required String tooltip,
    required void Function() onClick,
  }) {
    return button(
      type: .button,
      classes: 'table-search-segment${selected ? ' table-search-segment--active' : ''}',
      events: appTooltipEvents(context, text: tooltip),
      onClick: onClick,
      [.text(label)],
    );
  }
}

class _FilterRow extends StatelessComponent {
  const _FilterRow({
    required this.index,
    required this.row,
    required this.columnShapes,
    required this.columnOptions,
    required this.canRemove,
    required this.onUpdate,
    required this.onRemove,
  });

  final int index;
  final FilterConditionDraft row;
  final List<ColumnShape> columnShapes;
  final List<ZonaiSelectOption> columnOptions;
  final bool canRemove;
  final void Function(FilterConditionDraft) onUpdate;
  final void Function() onRemove;

  static String _conditionTitle(int index) => 'Condition ${index + 1}';
  static String _colLabelId(int index) => 'table-search-col-label-$index';
  static String _valLabelId(int index) => 'table-search-val-label-$index';

  @override
  Component build(BuildContext context) {
    final shape = resolveColumnShape(row.columnName, columnShapes);
    final operators = shape == null ? const <TableWhereOperator>[] : operatorsForColumn(shape);
    final op = row.operator;
    final needsValue = op?.needsValue ?? false;
    final enumListValues =
        needsValue && shape?.kind == ColumnShapeKind.enum_ && (op?.needsListValue ?? false);
    final conditionId = 'table-search-condition-$index';

    return div(
      classes: 'table-search-condition-card',
      attributes: {'id': conditionId, 'aria-labelledby': 'table-search-condition-badge-$index'},
      [
        div(classes: 'table-search-condition-card-header', [
          span(
            id: 'table-search-condition-badge-$index',
            classes: 'table-search-condition-badge',
            [.text(_conditionTitle(index))],
          ),
          if (canRemove)
            button(
              type: .button,
              classes: 'table-search-row-remove',
              attributes: {'aria-label': 'Remove ${_conditionTitle(index)}'},
              events: appTooltipEvents(context, text: 'Remove condition'),
              onClick: onRemove,
              [removeConditionIcon()],
            ),
        ]),
        div(classes: 'table-search-row-fields', [
          div(classes: 'table-search-row-inputs', [
            div(classes: 'table-search-field', [
              label(
                htmlFor: 'table-search-col-$index',
                classes: 'table-search-field-label',
                attributes: {'id': _colLabelId(index)},
                [.text('Column')],
              ),
              ZonaiSelect(
                id: 'table-search-col-$index',
                labelId: _colLabelId(index),
                value: row.columnName,
                placeholder: 'Choose column',
                options: columnOptions,
                onChange: (value) => onUpdate(draftForColumn(value, columnShapes)),
              ),
            ]),
            if (needsValue && !enumListValues && shape != null && op != null)
              div(classes: 'table-search-field', [
                label(
                  htmlFor: 'table-search-val-$index',
                  classes: 'table-search-field-label',
                  attributes: {'id': _valLabelId(index)},
                  [.text('Value')],
                ),
                TableFilterValueField(
                  id: 'table-search-val-$index',
                  shape: shape,
                  operator: op,
                  valueText: row.valueText,
                  boolValue: row.boolValue,
                  labelId: _valLabelId(index),
                  onValueTextChanged: (v) => onUpdate(row.copyWith(valueText: v)),
                  onBoolValueChanged: (v) => onUpdate(row.copyWith(boolValue: v)),
                ),
              ]),
          ]),
          if (enumListValues && shape != null && op != null)
            div(classes: 'table-search-field table-search-field--full', [
              label(
                htmlFor: 'table-search-val-$index',
                classes: 'table-search-field-label',
                attributes: {'id': _valLabelId(index)},
                [.text('Values')],
              ),
              TableFilterValueField(
                id: 'table-search-val-$index',
                shape: shape,
                operator: op,
                valueText: row.valueText,
                boolValue: row.boolValue,
                labelId: _valLabelId(index),
                onValueTextChanged: (v) => onUpdate(row.copyWith(valueText: v)),
                onBoolValueChanged: (v) => onUpdate(row.copyWith(boolValue: v)),
              ),
            ]),
          if (operators.isNotEmpty)
            div(classes: 'table-search-operators', [
              for (final operator in operators)
                button(
                  type: .button,
                  classes: [
                    'table-search-op',
                    if (op == operator) 'table-search-op--active',
                  ].join(' '),
                  attributes: {'aria-pressed': op == operator ? 'true' : 'false'},
                  events: appTooltipEvents(context, text: operator.tooltip),
                  onClick: () => onUpdate(row.copyWith(operator: operator)),
                  [.text(operator.label)],
                ),
            ]),
        ]),
      ],
    );
  }
}

Component searchIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 16.px,
    height: 16.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      circle(
        attributes: {
          'cx': '7',
          'cy': '7',
          'r': '4.25',
          'stroke': 'currentColor',
          'stroke-width': '1.5',
          'fill': 'none',
        },
        [],
      ),
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M10.25 10.25 13.5 13.5',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}

Component removeConditionIcon() {
  return svg(
    viewBox: '0 0 12 12',
    width: 14.px,
    height: 14.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M3 3l6 6M9 3 3 9',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}

/// Active filter summary for the table header subtitle.
String? tableFilterSubtitle(Where? appliedWhere, TableRowsData? data, List<ColumnShape> shapes) {
  if (appliedWhere == null || data == null) return null;
  final desc = describeAppliedWhere(appliedWhere, shapes);
  final s = data.total == 1 ? '' : 's';
  return '$desc · ${data.total} matching row$s';
}

/// Summary line shown in the search side panel header.
String? tableFilterPanelSummary(TableFilterState filter, List<ColumnShape> shapes) {
  if (!filter.hasAppliedFilter) return 'Build conditions and apply to filter rows.';
  return describeAppliedWhere(filter.appliedWhere!, shapes);
}

@css
List<StyleRule> tableSearchPanelStyles = [
  css('.table-detail-header-top').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(12.px),
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-detail-header-top .table-detail-title').styles(
    margin: .zero,
    flex: Flex(grow: 1, shrink: 1),
    minWidth: .zero,
    overflow: Overflow.hidden,
    raw: const {'text-overflow': 'ellipsis', 'white-space': 'nowrap'},
  ),
  css('.table-search-toggle').styles(
    width: 36.px,
    height: 36.px,
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    cursor: .pointer,
    radius: .all(Radius.circular(8.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    color: mutedColor,
    padding: .zero,
    position: Position.relative(),
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.table-search-toggle:hover').styles(backgroundColor: hoverColor, color: fgColor),
  css('.table-search-toggle--open').styles(
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    color: primaryColor,
  ),
  css('.table-search-toggle--active').styles(color: primaryColor),
  css('.table-search-toggle--active::after').styles(
    content: '""',
    position: Position.absolute(top: 6.px, right: 6.px),
    width: 6.px,
    height: 6.px,
    radius: .all(Radius.circular(3.px)),
    backgroundColor: primaryColor,
  ),
  css('.table-search-combine').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(6.px),
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-search-combine-label').styles(
    fontSize: 0.8125.rem,
    color: mutedColor,
    margin: .only(right: 4.px),
  ),
  css('.table-search-segment').styles(
    padding: .symmetric(horizontal: 10.px, vertical: 4.px),
    fontSize: 0.75.rem,
    fontWeight: .w600,
    cursor: .pointer,
    radius: .all(Radius.circular(6.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    color: mutedColor,
    raw: const {'font': 'inherit'},
  ),
  css('.table-search-segment--active').styles(
    backgroundColor: selectedBgColor,
    color: primaryColor,
    border: .all(color: primaryColor, width: 1.px, style: .solid),
  ),
  css('.table-search-conditions').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(12.px),
  ),
  css('.table-search-condition-card').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(10.px),
    padding: .all(12.px),
    radius: .all(Radius.circular(10.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    raw: const {'border-left': '3px solid var(--zonai-primary)'},
  ),
  css('.table-search-condition-card-header').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(8.px),
  ),
  css('.table-search-condition-badge').styles(
    fontSize: 0.75.rem,
    fontWeight: .w600,
    color: primaryColor,
    letterSpacing: 0.02.rem,
  ),
  css('.table-search-row-fields').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(8.px),
    minWidth: .zero,
  ),
  css('.table-search-row-inputs').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .start,
    gap: Gap.all(10.px),
    minWidth: .zero,
  ),
  css('.table-search-row-inputs .table-search-field').styles(
    flex: Flex(grow: 1, shrink: 1),
    minWidth: .zero,
  ),
  css('.table-search-field').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(4.px),
  ),
  css('.table-search-field--full').styles(width: 100.percent),
  css('.table-search-field--full + .table-search-operators').styles(margin: .only(top: 8.px)),
  css('.table-search-field-label').styles(
    fontSize: 0.75.rem,
    color: mutedColor,
    fontWeight: .w500,
  ),
  css('.table-search-operators').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(6.px),
  ),
  css('.table-search-op').styles(
    padding: .symmetric(horizontal: 8.px, vertical: 4.px),
    fontSize: 0.75.rem,
    cursor: .pointer,
    radius: .all(Radius.circular(6.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    color: fgColor,
    raw: const {'font': 'inherit', 'white-space': 'nowrap'},
  ),
  css('.table-search-op--active').styles(
    backgroundColor: selectedBgColor,
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    color: primaryColor,
  ),
  css('.table-search-row-remove').styles(
    width: 32.px,
    height: 32.px,
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    cursor: .pointer,
    radius: .all(Radius.circular(8.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    color: fgColor,
    padding: .zero,
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.table-search-row-remove:hover').styles(backgroundColor: hoverColor, color: errorColor),
  css('.table-search-panel-body').styles(
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(14.px),
    minHeight: .zero,
    overflow: Overflow.auto,
    padding: .symmetric(horizontal: 16.px, vertical: 12.px),
  ),
  css('.table-search-panel-footer').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(10.px),
    padding: .symmetric(horizontal: 16.px, vertical: 12.px),
    border: .only(top: BorderSide.solid(color: borderColor, width: 1.px)),
    backgroundColor: surfaceColor,
  ),
  css('.table-search-add-btn').styles(margin: .zero, fontSize: 0.8125.rem, alignSelf: .flexStart),
  css('.table-search-panel-actions-primary').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    gap: Gap.all(8.px),
    justifyContent: .end,
  ),
  css('.table-search-panel-actions-primary .z-btn + .z-btn').styles(margin: .zero),
  css('.table-filter-fk-value').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(8.px),
  ),
  css('.table-filter-fk-browse').styles(margin: .zero, alignSelf: .flexStart, fontSize: 0.8125.rem),
  css('.table-edit-chip-input').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(8.px),
  ),
  css('.table-edit-chip-input__chips').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(6.px),
  ),
  css('.table-edit-chip-input__chip').styles(
    display: .inlineFlex,
    alignItems: .center,
    gap: Gap.all(4.px),
    padding: .symmetric(horizontal: 8.px, vertical: 4.px),
    radius: .all(Radius.circular(6.px)),
    backgroundColor: selectedBgColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    fontSize: 0.8125.rem,
  ),
  css('.table-edit-chip-input__chip-remove').styles(
    width: 18.px,
    height: 18.px,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .zero,
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    radius: .all(Radius.circular(4.px)),
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.table-edit-chip-input__chip-remove:hover').styles(color: fgColor, backgroundColor: hoverColor),
  css('.table-edit-chip-input__add-row').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(6.px),
  ),
  css('.table-edit-chip-input__suggest').styles(fontSize: 0.8125.rem),
  css('.table-edit-chip-input__add-btn').styles(
    alignSelf: .start,
    padding: .symmetric(horizontal: 10.px, vertical: 6.px),
    fontSize: 0.75.rem,
    fontWeight: .w600,
    cursor: .pointer,
    radius: .all(Radius.circular(6.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    color: fgColor,
    raw: const {'font': 'inherit'},
  ),
  css('.table-edit-enum-values--empty').styles(
    fontSize: 0.8125.rem,
    color: mutedColor,
    raw: const {'line-height': '1.4'},
  ),
  css.media(MediaQuery.all(maxWidth: 640.px), [
    css('.table-search-row-inputs').styles(flexDirection: FlexDirection.column),
    css('.table-search-condition-badge').styles(display: .block),
  ]),
];

/// Side panel chrome styles (backdrop, fixed panel, resize).
@css
List<StyleRule> tableSearchSidePanelStyles = [
  css('.table-search-backdrop').styles(
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    opacity: 0,
    transition: Transition('opacity', duration: const Duration(milliseconds: 250), curve: Curve.easeOut),
    raw: const {
      'z-index': '160',
      'background-color': 'rgb(15 23 42 / 0.35)',
      'pointer-events': 'none',
    },
  ),
  css('.table-search-backdrop.table-search--open').styles(
    opacity: 1,
    raw: const {'pointer-events': 'auto'},
  ),
  css('.table-search-side-panel').styles(
    position: Position.fixed(top: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    flexDirection: FlexDirection.column,
    minHeight: .zero,
    height: 100.percent,
    overflow: Overflow.hidden,
    border: .only(left: BorderSide.solid(color: borderColor, width: 1.px)),
    backgroundColor: surfaceColor,
    transform: Transform.translate(x: 100.percent),
    transition: Transition('transform', duration: const Duration(milliseconds: 250), curve: Curve.easeOut),
    raw: const {
      'z-index': '160',
      'min-width': '320px',
      'max-width': '50vw',
      'box-shadow': '-8px 0 24px rgb(15 23 42 / 0.12)',
      'outline': 'none',
    },
  ),
  css('.table-search-side-panel.table-search--open').styles(transform: Transform.none),
  css('.table-search-side-panel.table-search--resizing').styles(
    userSelect: .none,
    raw: const {'transition': 'none', 'cursor': 'ew-resize'},
  ),
  css('.table-search-resize-handle').styles(
    position: Position.absolute(top: 0.px, left: 0.px, bottom: 0.px),
    width: 20.px,
    display: .block,
    backgroundColor: Colors.transparent,
    raw: const {'cursor': 'ew-resize', 'touch-action': 'none', 'z-index': '10'},
  ),
  css('.table-search-side-main').styles(
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    minHeight: .zero,
    height: 100.percent,
    padding: .only(left: 20.px),
    overflow: Overflow.hidden,
  ),
  css('.table-search-side-header').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(4.px),
    padding: .symmetric(horizontal: 16.px, vertical: 16.px),
    border: .only(bottom: BorderSide.solid(color: borderColor, width: 1.px)),
  ),
  css('.table-search-side-header-row').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(12.px),
  ),
  css('.table-search-side-title').styles(
    margin: .zero,
    fontSize: 1.125.rem,
    fontWeight: .w600,
  ),
  css('.table-search-side-summary').styles(
    margin: .zero,
    fontSize: 0.8125.rem,
    color: mutedColor,
    raw: const {'line-height': '1.45'},
  ),
  css('.table-search-side-close').styles(
    width: 32.px,
    height: 32.px,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    cursor: .pointer,
    radius: .all(Radius.circular(8.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    color: fgColor,
    padding: .zero,
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.table-search-side-close:hover').styles(backgroundColor: hoverColor),
];
