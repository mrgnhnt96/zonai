import 'package:jaspr/dom.dart';

import '../../constants/theme.dart';

/// Shared styles for chip inputs and FK editors (row detail + filters).
@css
List<StyleRule> get tableEditSharedStyles => [
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
  css('.table-edit-chip-input__chip-remove:hover').styles(
    color: fgColor,
    backgroundColor: hoverColor,
  ),
  css('.table-edit-chip-input__add-row').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(6.px),
  ),
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
  css('.table-edit-fk-value').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    alignItems: .center,
    gap: Gap.all(8.px),
  ),
  css('.table-edit-fk-value__chip').styles(
    padding: .symmetric(horizontal: 8.px, vertical: 4.px),
    radius: .all(Radius.circular(6.px)),
    backgroundColor: selectedBgColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    fontSize: 0.8125.rem,
    raw: const {'font-family': 'ui-monospace, monospace'},
  ),
  css('.table-edit-fk-value__input').styles(
    flex: Flex(grow: 1, shrink: 1),
    minWidth: 120.px,
  ),
  css('.table-edit-fk-browse').styles(margin: .zero, fontSize: 0.8125.rem),
  css('.table-filter-fk-value').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(8.px),
  ),
  css('.table-filter-fk-browse').styles(margin: .zero, alignSelf: .flexStart, fontSize: 0.8125.rem),
];
