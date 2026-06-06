import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../constants/button_sizes.dart';
import '../constants/layout.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/session_user_provider.dart';
import '../providers/table_filter_provider.dart';
import '../providers/table_focus_provider.dart';
import '../providers/table_row_create_provider.dart';
import '../providers/table_rows_provider.dart';
import '../providers/resolved_collection_provider.dart';
import '../providers/table_schema_provider.dart';
import '../utils/table_cell_edit.dart';
import '../utils/table_row_edit.dart';
import '../utils/table_where_build.dart';
import '../utils/table_where_format.dart';
import '../utils/table_where_operators.dart';
import 'app_tooltip_overlay.dart';
import 'query_preview_card.dart';
import 'syntax_highlighted_code.dart';
import 'table_filter_value_field.dart';
import 'theme/theme_components.dart';

enum _SearchPreviewMode { json, dart }

/// Search toggle for the table header (opens side panel).
class TableSearchToggle extends StatelessComponent {
  const TableSearchToggle({super.key});

  @override
  Component build(BuildContext context) {
    final filter = context.watch(tableFilterProvider);
    final notifier = context.read(tableFilterProvider.notifier);

    return ZonaiIconButton(
      size: ZonaiIconButtonSize.md,
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
      child: searchIcon(),
    );
  }
}

/// Create-row toggle for the table header (opens the row detail panel in create mode).
class TableCreateRowToggle extends StatelessComponent {
  const TableCreateRowToggle({super.key});

  @override
  Component build(BuildContext context) {
    final create = context.watch(tableRowCreateProvider);
    final focus = context.watch(tableFocusProvider);
    final schema = context.watch(tableSchemaProvider);
    final shapes = schema?.columns ?? const <ColumnShape>[];
    final sqliteName = focus?.sqliteName ?? '';
    if (shapes.isEmpty || sqliteName.isEmpty) {
      return Component.empty();
    }

    final allActions = context.watch(tableCollectionActionsProvider);
    final sessionCanEdit = context.watch(sessionUserProvider)?.canEdit == true;
    if (!canCreateTableRows(
      allActions: allActions,
      actions: allActions[sqliteName],
      sessionCanEdit: sessionCanEdit,
      sqliteName: sqliteName,
      columnShapes: shapes,
    )) {
      return Component.empty();
    }

    final columns = [for (final shape in shapes) shape.name];
    final notifier = context.read(tableRowCreateProvider.notifier);
    final isOpen = create != null;

    return ZonaiIconButton(
      size: ZonaiIconButtonSize.md,
      classes: ['table-create-toggle', if (isOpen) 'table-create-toggle--open'].join(' '),
      attributes: {'aria-label': 'Create row', 'aria-expanded': isOpen ? 'true' : 'false'},
      events: appTooltipEvents(context, text: 'Create row'),
      onClick: () {
        if (isOpen) {
          notifier.requestClose();
        } else {
          notifier.open(sqliteName: sqliteName, columns: columns, columnShapes: shapes);
        }
      },
      child: createRowIcon(),
    );
  }
}

/// Filter builder body (rendered inside [TableSearchSidePanel]).
class TableSearchPanel extends StatelessComponent {
  const TableSearchPanel({required this.columnShapes, required this.state, required this.tableName, super.key});

  final List<ColumnShape> columnShapes;
  final TableFilterState state;
  final String tableName;

  @override
  Component build(BuildContext context) {
    final notifier = context.read(tableFilterProvider.notifier);
    final showCombine = state.draftRows.length > 1;
    final columnOptions = [
      for (final shape in columnShapes) ZonaiSelectOption(value: shape.name, label: columnShapeHeaderLabel(shape)),
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
        ZonaiButton(
          variant: ZonaiButtonVariant.ghost,
          size: ZonaiButtonSize.sm,
          classes: 'table-search-add-btn',
          onClick: notifier.addRow,
          child: .text('+ Add filter'),
        ),
        _SearchFilterPreview(tableName: tableName, state: state, columnShapes: columnShapes),
        div(classes: 'table-search-panel-actions-primary', [
          ZonaiButton(variant: ZonaiButtonVariant.secondary, onClick: notifier.clear, child: const .text('Clear')),
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

class _SearchFilterPreview extends StatefulComponent {
  const _SearchFilterPreview({required this.tableName, required this.state, required this.columnShapes});

  final String tableName;
  final TableFilterState state;
  final List<ColumnShape> columnShapes;

  @override
  State<_SearchFilterPreview> createState() => _SearchFilterPreviewState();
}

class _SearchFilterPreviewState extends State<_SearchFilterPreview> {
  var _expanded = false;
  _SearchPreviewMode _mode = _SearchPreviewMode.json;

  @override
  Component build(BuildContext context) {
    final result = buildWhereFromDraft(
      rows: component.state.draftRows,
      combine: component.state.combine,
      columnShapes: component.columnShapes,
    );

    final showDart = _mode == _SearchPreviewMode.dart;
    final previewLabel = showDart ? 'Dart' : 'JSON';
    final previewText = switch (result) {
      TableWhereBuildSuccess(:final where) =>
        showDart
            ? formatListBodyDart(table: component.tableName, where: where)
            : formatListBodyJson(table: component.tableName, where: where),
      TableWhereBuildError() => '',
    };

    return div(classes: 'table-search-preview', [
      div(classes: 'home-sidebar-system table-search-preview-system', [
        button(
          type: .button,
          classes: 'home-sidebar-system-toggle',
          attributes: {'aria-expanded': _expanded ? 'true' : 'false'},
          onClick: () => setState(() => _expanded = !_expanded),
          [
            span(classes: 'home-sidebar-system-chevron${_expanded ? ' home-sidebar-system-chevron--open' : ''}', [
              .text('›'),
            ]),
            span(classes: ZonaiClasses.sectionLabel, [.text('Generated query')]),
          ],
        ),
        div(
          classes: 'home-sidebar-system-panel${_expanded ? ' home-sidebar-system-panel--shown' : ''}',
          attributes: {'aria-hidden': _expanded ? 'false' : 'true'},
          [
            div(classes: 'home-sidebar-system-panel-inner', [
              div(
                classes: 'table-search-combine table-search-preview-format',
                attributes: {'role': 'group', 'aria-label': 'Preview format'},
                [
                  _previewFormatSegment(
                    label: 'JSON',
                    selected: !showDart,
                    onSelect: () => setState(() => _mode = _SearchPreviewMode.json),
                  ),
                  _previewFormatSegment(
                    label: 'Dart',
                    selected: showDart,
                    onSelect: () => setState(() => _mode = _SearchPreviewMode.dart),
                  ),
                ],
              ),
              switch (result) {
                TableWhereBuildError(:final message) => p(classes: 'table-search-preview-hint', [.text(message)]),
                TableWhereBuildSuccess() => div(classes: 'table-search-preview-code', [
                  QueryPreviewCard(
                    label: previewLabel,
                    text: previewText,
                    highlightLanguage: showDart ? SyntaxHighlightLanguage.dart : SyntaxHighlightLanguage.json,
                  ),
                ]),
              },
            ]),
          ],
        ),
      ]),
    ]);
  }
}

Component _previewFormatSegment({required String label, required bool selected, required void Function() onSelect}) {
  return button(
    type: .button,
    classes: ['table-search-segment', if (selected) 'table-search-segment--active'].join(' '),
    attributes: {'aria-pressed': selected ? 'true' : 'false'},
    onClick: onSelect,
    [.text(label)],
  );
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
    final enumListValues = needsValue && shape?.kind == ColumnShapeKind.enum_ && (op?.needsListValue ?? false);
    final dateTimeValue = needsValue && shape != null && isDateTimeColumnKind(shape.kind) && !enumListValues;
    final conditionId = 'table-search-condition-$index';

    return div(
      classes: 'table-search-condition-card',
      attributes: {'id': conditionId, 'aria-labelledby': 'table-search-condition-badge-$index'},
      [
        div(classes: 'table-search-condition-card-header', [
          span(id: 'table-search-condition-badge-$index', classes: 'table-search-condition-badge', [
            .text(_conditionTitle(index)),
          ]),
          if (canRemove)
            ZonaiIconButton(
              size: ZonaiIconButtonSize.sm,
              classes: 'table-search-row-remove',
              attributes: {'aria-label': 'Remove ${_conditionTitle(index)}'},
              events: appTooltipEvents(context, text: 'Remove condition'),
              onClick: onRemove,
              child: removeConditionIcon(),
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
            if (needsValue && !enumListValues && !dateTimeValue && shape != null && op != null)
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
                  dateTimeUseUtc: row.dateTimeUseUtc,
                  onDateTimeUseUtcChanged: (v) => onUpdate(row.copyWith(dateTimeUseUtc: v)),
                  labelId: _valLabelId(index),
                  onValueTextChanged: (v) => onUpdate(row.copyWith(valueText: v)),
                  onBoolValueChanged: (v) => onUpdate(row.copyWith(boolValue: v)),
                ),
              ]),
          ]),
          if ((enumListValues || dateTimeValue) && shape != null && op != null)
            div(classes: 'table-search-field table-search-field--full', [
              label(
                htmlFor: 'table-search-val-$index',
                classes: 'table-search-field-label',
                attributes: {'id': _valLabelId(index)},
                [.text(enumListValues ? 'Values' : 'Value')],
              ),
              TableFilterValueField(
                id: 'table-search-val-$index',
                shape: shape,
                operator: op,
                valueText: row.valueText,
                boolValue: row.boolValue,
                dateTimeUseUtc: row.dateTimeUseUtc,
                onDateTimeUseUtcChanged: (v) => onUpdate(row.copyWith(dateTimeUseUtc: v)),
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
                  classes: ['table-search-op', if (op == operator) 'table-search-op--active'].join(' '),
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

Component createRowIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 16.px,
    height: 16.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M8 3.5v9M3.5 8h9',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
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
  css('.table-search-toggle').styles(position: Position.relative()),
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
  css('.table-create-toggle').styles(position: Position.relative()),
  css('.table-create-toggle--open').styles(
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    color: primaryColor,
  ),
  css('.table-search-combine').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s3),
    flex: Flex(grow: 0, shrink: 0),
  ),
  css('.table-search-combine-label').styles(
    fontSize: 0.8125.rem,
    color: mutedColor,
    margin: .only(right: ZonaiSpacing.s2),
  ),
  css('.table-search-segment').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.xxs),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.xxs),
    fontWeight: .w600,
    cursor: .pointer,
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.xxs))),
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
  css('.table-edit-datetime__time-inputs .table-edit-datetime__ampm').styles(
    flex: Flex(grow: 0, shrink: 0),
    gap: Gap.all(ZonaiSpacing.s2),
    padding: .all(ZonaiSpacing.s1_5),
    radius: .all(Radius.circular(8.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: hoverColor,
  ),
  css('.table-edit-datetime__time-inputs .table-search-segment').styles(
    minWidth: 36.px,
    padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s3),
    textAlign: TextAlign.center,
    raw: const {'appearance': 'none', '-webkit-appearance': 'none'},
  ),
  css('.table-edit-datetime__time-inputs .table-search-segment--active').styles(
    backgroundColor: primaryColor,
    color: onPrimaryColor,
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    fontWeight: .w700,
  ),
  css('.table-edit-datetime__time-inputs .table-search-segment--active:hover').styles(
    backgroundColor: primaryHoverColor,
    border: .all(color: primaryHoverColor, width: 1.px, style: .solid),
    color: onPrimaryColor,
  ),
  css(
    '.table-search-conditions',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s6)),
  css('.table-search-condition-card').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s5),
    padding: .all(ZonaiSpacing.s6),
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
    gap: Gap.all(ZonaiSpacing.s4),
  ),
  css(
    '.table-search-condition-badge',
  ).styles(fontSize: 0.75.rem, fontWeight: .w600, color: primaryColor, letterSpacing: 0.02.rem),
  css(
    '.table-search-row-fields',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s4), minWidth: .zero),
  css('.table-search-row-inputs').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .start,
    gap: Gap.all(ZonaiSpacing.s5),
    minWidth: .zero,
  ),
  css('.table-search-row-inputs .table-search-field').styles(flex: Flex(grow: 1, shrink: 1), minWidth: .zero),
  css('.table-search-field').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2)),
  css('.table-search-field--full').styles(width: 100.percent),
  css('.table-search-field--full + .table-search-operators').styles(margin: .only(top: ZonaiSpacing.s4)),
  css('.table-search-field-label').styles(fontSize: 0.75.rem, color: mutedColor, fontWeight: .w500),
  css(
    '.table-search-operators',
  ).styles(display: .flex, flexDirection: FlexDirection.row, flexWrap: FlexWrap.wrap, gap: Gap.all(ZonaiSpacing.s3)),
  css('.table-search-op').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.xxs),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.xxs),
    cursor: .pointer,
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.xxs))),
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
  css('.table-search-row-remove').styles(flex: Flex(grow: 0, shrink: 0)),
  css('.table-search-row-remove:hover').styles(color: errorColor),
  css('.table-search-panel-body').styles(
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s7),
    minHeight: .zero,
    overflow: Overflow.auto,
    padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s6),
  ),
  css('.table-search-preview').styles(flex: Flex(grow: 0, shrink: 0), width: 100.percent),
  css(
    '.table-search-preview-system',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2), width: 100.percent),
  css('.table-search-preview-system .home-sidebar-system-toggle').styles(
    cursor: .pointer,
    padding: .symmetric(vertical: ZonaiSpacing.s2),
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s3),
    width: 100.percent,
    border: Border.none,
    backgroundColor: Colors.transparent,
    textAlign: .left,
    outline: Outline(style: OutlineStyle.none),
    raw: const {'font': 'inherit', 'appearance': 'none', '-webkit-appearance': 'none'},
  ),
  css('.table-search-preview-system .home-sidebar-system-toggle:hover').styles(
    backgroundColor: Colors.transparent,
    raw: const {'& .home-sidebar-system-chevron': 'color: var(--zonai-fg)'},
  ),
  css('.table-search-preview-system .home-sidebar-system-toggle:focus-visible').styles(
    backgroundColor: Colors.transparent,
    raw: const {'box-shadow': '0 0 0 2px var(--zonai-focus-ring)', 'border-radius': '4px'},
  ),
  css('.table-search-preview-system .home-sidebar-system-toggle:active').styles(backgroundColor: Colors.transparent),
  css('.table-search-preview-system .home-sidebar-system-chevron').styles(
    display: .inlineFlex,
    alignItems: .center,
    justifyContent: .center,
    width: 14.px,
    fontSize: 0.875.rem,
    fontWeight: .w700,
    color: mutedColor,
    flex: Flex(grow: 0, shrink: 0),
    raw: const {'line-height': '1', 'transition': 'transform 0.15s ease'},
  ),
  css(
    '.table-search-preview-system .home-sidebar-system-chevron--open',
  ).styles(raw: const {'transform': 'rotate(90deg)'}),
  css(
    '.table-search-preview-system .home-sidebar-system-panel',
  ).styles(raw: const {'display': 'grid', 'grid-template-rows': '0fr', 'transition': 'grid-template-rows 0.2s ease'}),
  css(
    '.table-search-preview-system .home-sidebar-system-panel--shown',
  ).styles(raw: const {'grid-template-rows': '1fr'}),
  css('.table-search-preview-system .home-sidebar-system-panel-inner').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s4),
    overflow: Overflow.hidden,
    minHeight: .zero,
  ),
  css('.table-search-preview-format').styles(
    flex: Flex(grow: 0, shrink: 0),
    gap: Gap.all(ZonaiSpacing.s2),
    padding: .all(ZonaiSpacing.s1_5),
    radius: .all(Radius.circular(8.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: hoverColor,
  ),
  css('.table-search-preview-format .table-search-segment').styles(
    minWidth: 36.px,
    padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s3),
    textAlign: TextAlign.center,
    border: Border.none,
    radius: .all(Radius.circular(6.px)),
    raw: const {'appearance': 'none', '-webkit-appearance': 'none'},
  ),
  css(
    '.table-search-preview-format .table-search-segment--active',
  ).styles(backgroundColor: primaryColor, color: onPrimaryColor, border: Border.none, fontWeight: .w700),
  css(
    '.table-search-preview-format .table-search-segment--active:hover',
  ).styles(backgroundColor: primaryHoverColor, color: onPrimaryColor),
  css('.table-search-preview-code .table-row-detail-json-card-toolbar').styles(
    position: Position.absolute(top: 6.px, right: 6.px),
  ),
  css('.table-search-preview-code .table-row-detail-json-card-pre').styles(
    margin: .zero,
    padding: .only(top: ZonaiSpacing.s11_5, left: ZonaiSpacing.s6, right: ZonaiSpacing.s6, bottom: ZonaiSpacing.s6),
  ),
  css(
    '.table-search-preview-hint',
  ).styles(margin: .zero, fontSize: 0.8125.rem, color: mutedColor, raw: const {'line-height': '1.45'}),
  css('.table-search-panel-footer').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s5),
    padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s6),
    border: .only(
      top: BorderSide.solid(color: borderColor, width: 1.px),
    ),
    backgroundColor: surfaceColor,
  ),
  css('.table-search-add-btn').styles(margin: .zero, alignSelf: .flexStart),
  css(
    '.table-search-panel-actions-primary',
  ).styles(display: .flex, flexDirection: FlexDirection.row, gap: Gap.all(ZonaiSpacing.s4), justifyContent: .end),
  css('.table-search-panel-actions-primary .z-btn + .z-btn').styles(margin: .zero),
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
    raw: const {'z-index': '160', 'background-color': 'rgb(15 23 42 / 0.35)', 'pointer-events': 'none'},
  ),
  css('.table-search-backdrop.table-search--open').styles(opacity: 1, raw: const {'pointer-events': 'auto'}),
  css('.table-search-side-panel').styles(
    position: Position.fixed(top: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    flexDirection: FlexDirection.column,
    minHeight: .zero,
    height: 100.percent,
    overflow: Overflow.hidden,
    border: .only(
      left: BorderSide.solid(color: borderColor, width: 1.px),
    ),
    backgroundColor: surfaceColor,
    transform: Transform.translate(x: 100.percent),
    transition: Transition('transform', duration: const Duration(milliseconds: 250), curve: Curve.easeOut),
    raw: const {
      'z-index': '160',
      'min-width': '320px',
      'max-width': '75vw',
      'box-shadow': '-8px 0 24px rgb(15 23 42 / 0.12)',
      'outline': 'none',
    },
  ),
  css('.table-search-side-panel.table-search--open').styles(transform: Transform.none),
  css(
    '.table-search-side-panel.table-search--resizing',
  ).styles(userSelect: .none, raw: const {'transition': 'none', 'cursor': 'ew-resize'}),
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
    overflow: Overflow.hidden,
  ),
  css('.table-search-side-header').styles(
    flex: Flex(grow: 0, shrink: 0),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s2),
    padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s8),
    border: .only(
      bottom: BorderSide.solid(color: borderColor, width: 1.px),
    ),
  ),
  css('.table-search-side-header-row').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    justifyContent: .spaceBetween,
    gap: Gap.all(ZonaiSpacing.s6),
  ),
  css('.table-search-side-title').styles(margin: .zero, fontSize: 1.125.rem, fontWeight: .w600),
  css(
    '.table-search-side-summary',
  ).styles(margin: .zero, fontSize: 0.8125.rem, color: mutedColor, raw: const {'line-height': '1.45'}),
  css.media(MediaQuery.all(maxWidth: ZonaiLayout.mobilePanelBreakpointPx.px), [
    css('.table-search-side-panel').styles(width: 100.percent, raw: const {'max-width': '100%', 'min-width': '100%'}),
    css('.table-search-resize-handle').styles(display: .none),
  ]),
];
