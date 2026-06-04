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
    alignItems: .start,
    alignSelf: .stretch,
    gap: Gap.all(6.px),
    width: 100.percent,
  ),
  css('.table-edit-chip-input__add-input').styles(
    display: .block,
    width: 100.percent,
    alignSelf: .stretch,
  ),
  css('.table-edit-chip-input__add-row .z-btn').styles(
    alignSelf: .start,
    margin: .zero,
  ),
  css('.table-edit-boolean').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(10.px),
    flexWrap: FlexWrap.wrap,
  ),
  css('.table-edit-boolean__label').styles(
    display: .inlineFlex,
    alignItems: .center,
    gap: Gap.all(8.px),
    cursor: .pointer,
    fontSize: 0.9375.rem,
    color: fgColor,
    raw: const {'font': 'inherit'},
  ),
  css('.table-edit-boolean__checkbox').styles(
    width: 16.px,
    height: 16.px,
    margin: .zero,
    cursor: .pointer,
    raw: const {'accent-color': 'var(--zonai-primary)'},
  ),
  css('.table-edit-json-field').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(6.px),
    width: 100.percent,
  ),
  css('.table-edit-json-field__error').styles(
    margin: .zero,
    fontSize: 0.8125.rem,
    color: errorColor,
    raw: const {'line-height': '1.45'},
  ),
  css('.table-edit-boolean__hint').styles(
    fontSize: 0.8125.rem,
    fontWeight: .w400,
    fontStyle: FontStyle.italic,
    color: mutedColor,
    raw: const {'line-height': '1.45'},
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
  css('.table-filter-fk-value').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(8.px),
  ),
  css('.table-edit-enum-values--empty').styles(
    fontSize: 0.8125.rem,
    color: mutedColor,
    raw: const {'line-height': '1.4'},
  ),
];
