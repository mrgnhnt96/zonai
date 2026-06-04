import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../../constants/theme.dart';
import '../../providers/foreign_key_rows_provider.dart';
import '../../providers/table_rows_provider.dart';
import '../theme/ui_styles.dart';
import '../../constants/spacing.dart';

/// Modal to pick one row from a foreign-key target table.
class ForeignKeyPickerDialog extends StatelessComponent {
  const ForeignKeyPickerDialog({
    super.key,
    required this.foreignKey,
    required this.selectedId,
    required this.onSelect,
    required this.onClose,
  });

  final ForeignKeyShape foreignKey;
  final String? selectedId;
  final void Function(String? id) onSelect;
  final VoidCallback onClose;

  @override
  Component build(BuildContext context) {
    final asyncRows = context.watch(foreignKeyRowsProvider(foreignKey));

    return div(
      classes: 'fk-picker-backdrop',
      events: {'click': (_) => onClose()},
      [
        div(
          classes: 'fk-picker-dialog',
          attributes: {
            'role': 'dialog',
            'aria-modal': 'true',
            'aria-labelledby': 'fk-picker-title',
          },
          events: {'click': (event) => event.stopPropagation()},
          [
            div(classes: 'fk-picker-header', [
              h3(id: 'fk-picker-title', classes: 'fk-picker-title', [
                .text('Select ${foreignKey.table}'),
              ]),
              button(
                type: .button,
                classes: 'fk-picker-close',
                attributes: {'aria-label': 'Close'},
                onClick: onClose,
                [_closeIcon()],
              ),
            ]),
            div(classes: 'fk-picker-search-row', [
              input<String>(
                id: 'fk-picker-search',
                type: .text,
                classes: ZonaiClasses.input,
                attributes: {
                  'placeholder': 'Search rows…',
                  'autocomplete': 'off',
                  'readonly': '',
                  'aria-disabled': 'true',
                  'title': 'Search coming soon',
                },
                value: '',
                onInput: (_) {},
              ),
            ]),
            div(classes: 'fk-picker-body', [
              switch (asyncRows) {
                AsyncLoading() => p(classes: 'fk-picker-status', [.text('Loading…')]),
                AsyncError(:final error) => p(classes: 'fk-picker-status fk-picker-status--error', [
                  .text('Failed to load: $error'),
                ]),
                AsyncData(:final value) when value == null || value.rows.isEmpty =>
                  p(classes: 'fk-picker-status', [.text('No rows found.')]),
                AsyncData(:final value) => _FkPickerTable(
                  data: value!,
                  foreignKey: foreignKey,
                  selectedId: selectedId,
                  onSelect: onSelect,
                ),
              },
            ]),
            div(classes: 'fk-picker-footer', [
              if (selectedId != null)
                button(
                  type: .button,
                  classes: '${ZonaiClasses.btn} ${ZonaiClasses.btnGhost}',
                  onClick: () {
                    onSelect(null);
                    onClose();
                  },
                  [.text('Clear')],
                ),
              button(
                type: .button,
                classes: '${ZonaiClasses.btn} ${ZonaiClasses.btnSecondary}',
                onClick: onClose,
                [.text('Cancel')],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

class _FkPickerTable extends StatelessComponent {
  const _FkPickerTable({
    required this.data,
    required this.foreignKey,
    required this.selectedId,
    required this.onSelect,
  });

  final TableRowsData data;
  final ForeignKeyShape foreignKey;
  final String? selectedId;
  final void Function(String? id) onSelect;

  @override
  Component build(BuildContext context) {
    final pkIndex = foreignKeyPrimaryColumnIndex(data, foreignKey);
    if (pkIndex == null) {
      return p(classes: 'fk-picker-status', [.text('Table has no columns.')]);
    }

    final displayColumns = <int>[
      pkIndex,
      for (var i = 0; i < data.columns.length; i++)
        if (i != pkIndex && i < 4) i,
    ];

    return div(classes: 'fk-picker-table-wrap', [
      table(classes: 'fk-picker-table', [
        thead([
          tr([
            for (final i in displayColumns)
              th([.text(data.columns[i])]),
          ]),
        ]),
        tbody([
          for (final row in data.rows)
            tr(
              classes: selectedId != null && '${row[pkIndex]}' == selectedId
                  ? 'fk-picker-row fk-picker-row--selected'
                  : 'fk-picker-row',
              events: {
                'click': (_) => onSelect('${row[pkIndex]}'),
              },
              [
                for (final i in displayColumns)
                  td([.text(row[i] == null ? '—' : '${row[i]}')]),
              ],
            ),
        ]),
      ]),
    ]);
  }
}

Component _closeIcon() {
  return svg(
    viewBox: '0 0 16 16',
    width: 16.px,
    height: 16.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M4 4l8 8M12 4 4 12',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}

@css
List<StyleRule> get foreignKeyPickerDialogStyles => [
  css('.fk-picker-backdrop').styles(
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .all(ZonaiSpacing.s11),
    raw: const {'z-index': '1200', 'background': 'rgba(0,0,0,0.4)'},
  ),
  css('.fk-picker-dialog').styles(
    width: 100.percent,
    maxWidth: 640.px,
    maxHeight: 80.vh,
    display: .flex,
    flexDirection: FlexDirection.column,
    backgroundColor: surfaceColor,
    radius: .all(Radius.circular(12.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': 'var(--zonai-shadow)'},
  ),
  css('.fk-picker-header').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .spaceBetween,
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s8),
    raw: const {'border-bottom': '1px solid var(--zonai-border)'},
  ),
  css('.fk-picker-title').styles(
    margin: .zero,
    fontSize: 1.125.rem,
    fontWeight: .w600,
  ),
  css('.fk-picker-close').styles(
    display: .flex,
    padding: .all(ZonaiSpacing.s3),
    border: Border.none,
    backgroundColor: Colors.transparent,
    cursor: .pointer,
    color: mutedColor,
  ),
  css('.fk-picker-search-row').styles(padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s6)),
  css('.fk-picker-body').styles(
    flex: Flex(grow: 1, shrink: 1),
    overflow: Overflow.auto,
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s4),
    minHeight: 120.px,
  ),
  css('.fk-picker-status').styles(color: mutedColor, fontSize: 0.875.rem),
  css('.fk-picker-status--error').styles(color: errorColor),
  css('.fk-picker-table-wrap').styles(overflow: Overflow.auto, width: 100.percent),
  css('.fk-picker-table').styles(
    width: 100.percent,
    fontSize: 0.875.rem,
    raw: const {'border-collapse': 'collapse'},
  ),
  css('.fk-picker-table th').styles(
    textAlign: TextAlign.left,
    padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s4),
    color: mutedColor,
    fontWeight: .w500,
    raw: const {'border-bottom': '1px solid var(--zonai-border)'},
  ),
  css('.fk-picker-table td').styles(
    padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s4),
    raw: const {'border-bottom': '1px solid var(--zonai-border)'},
  ),
  css('.fk-picker-row').styles(cursor: .pointer),
  css('.fk-picker-row:hover td').styles(backgroundColor: hoverColor),
  css('.fk-picker-row--selected td').styles(backgroundColor: selectedBgColor),
  css('.fk-picker-footer').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    justifyContent: .end,
    gap: Gap.all(ZonaiSpacing.s4),
    padding: .symmetric(horizontal: ZonaiSpacing.s10, vertical: ZonaiSpacing.s7),
    raw: const {'border-top': '1px solid var(--zonai-border)'},
  ),
];
