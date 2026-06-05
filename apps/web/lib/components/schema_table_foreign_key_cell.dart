import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../providers/foreign_key_reference_lookup_provider.dart';
import '../providers/foreign_key_rows_provider.dart';
import '../providers/table_row_detail_provider.dart';
import 'app_tooltip_overlay.dart';
import 'theme/zonai_tag.dart';

/// FK table cell: resolved label tag and a button to open referenced row details.
class SchemaTableForeignKeyCell extends StatelessComponent {
  const SchemaTableForeignKeyCell({
    required this.rawValue,
    required this.shape,
    super.key,
  });

  final Object? rawValue;
  final ColumnShape shape;

  @override
  Component build(BuildContext context) {
    final value = rawValue;
    if (value == null) return .text('—');

    final foreignKey = shape.foreignKey;
    if (foreignKey == null) {
      return .text(formatSchemaCell(value, shape));
    }

    final fallbackLabel = formatSchemaCell(value, shape);
    final query = ForeignKeyReferenceLookupQuery(foreignKey: foreignKey, rawValue: value);
    final asyncReferenced = context.watch(foreignKeyReferenceLookupProvider(query));

    return switch (asyncReferenced) {
      AsyncLoading() => _ForeignKeyCellContent(
        label: fallbackLabel,
        monospace: true,
        canOpenDetails: false,
      ),
      AsyncData(:final value) => _ForeignKeyCellContent(
        label: value?.displayLabel ?? fallbackLabel,
        monospace: value?.displayLabel == null,
        canOpenDetails: value != null,
        onOpenDetails: value == null ? null : () => _openReferencedRow(context, value),
      ),
      AsyncError() => _ForeignKeyCellContent(
        label: fallbackLabel,
        monospace: true,
        canOpenDetails: false,
      ),
    };
  }

  void _openReferencedRow(BuildContext context, ForeignKeyReferencedRow referenced) {
    context.read(tableRowDetailProvider.notifier).open(
      rowKey: referenced.rowKey,
      row: referenced.row,
      sqliteName: referenced.sqliteName,
      columns: referenced.columns,
      columnShapes: referenced.columnShapes,
    );
  }
}

class _ForeignKeyCellContent extends StatelessComponent {
  const _ForeignKeyCellContent({
    required this.label,
    required this.monospace,
    required this.canOpenDetails,
    this.onOpenDetails,
  });

  final String label;
  final bool monospace;
  final bool canOpenDetails;
  final VoidCallback? onOpenDetails;

  @override
  Component build(BuildContext context) {
    return div(classes: 'rows-fk-cell', [
      ZonaiTag(label: label, monospace: monospace),
      if (canOpenDetails)
        button(
          classes: 'rows-fk-cell__details-btn',
          type: .button,
          attributes: {'aria-label': 'View referenced row details'},
          events: {
            'click': (event) {
              event.stopPropagation();
              context.read(appTooltipProvider.notifier).hide();
              onOpenDetails?.call();
            },
            ...appTooltipEvents(context, text: 'View referenced row'),
          },
          [_referencedRowDetailsIcon()],
        ),
    ]);
  }
}

Component _referencedRowDetailsIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 14.px,
    height: 14.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M5.5 3.25h8.25a.75.75 0 0 1 .75.75v8a.75.75 0 0 1-.75.75H5.5a.75.75 0 0 1-.75-.75V4a.75.75 0 0 1 .75-.75Z',
        attributes: const {'stroke-linejoin': 'round'},
        [],
      ),
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M2.75 5.25v5.5a.75.75 0 0 0 .75.75H4',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
}

@css
List<StyleRule> get schemaTableForeignKeyCellStyles => [
  css('.rows-fk-cell').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(6.px),
    flexWrap: FlexWrap.wrap,
    minWidth: .zero,
  ),
  css('.rows-fk-cell__details-btn').styles(
    display: .inlineFlex,
    alignItems: .center,
    justifyContent: .center,
    width: 1.5.rem,
    height: 1.5.rem,
    padding: .zero,
    margin: .zero,
    border: .unset,
    radius: .all(Radius.circular(5.px)),
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    flex: Flex(grow: 0, shrink: 0),
    raw: const {'line-height': '0'},
  ),
  css('.rows-fk-cell__details-btn:hover:not(:disabled)').styles(
    backgroundColor: hoverColor,
    color: fgColor,
  ),
  css('.rows-fk-cell__details-btn:focus-visible').styles(
    raw: const {'outline': '2px solid var(--zonai-primary)', 'outline-offset': '1px'},
  ),
];
