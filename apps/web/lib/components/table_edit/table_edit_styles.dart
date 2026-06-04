import 'package:jaspr/dom.dart';

import '../../constants/theme.dart';
import '../../constants/spacing.dart';

/// Shared styles for chip inputs and FK editors (row detail + filters).
@css
List<StyleRule> get tableEditSharedStyles => [
  css('.table-edit-chip-input').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s4),
  ),
  css('.table-edit-chip-input__chips').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(ZonaiSpacing.s3),
    raw: const {'--table-edit-chip-gap': '6px'},
  ),
  css('.table-edit-chip-input__chips--dragging').styles(
    raw: const {'user-select': 'none'},
  ),
  css('.table-edit-chip-input__chip-item').styles(
    position: Position.relative(),
    display: .inlineFlex,
    alignItems: .center,
  ),
  css('.table-edit-chip-input__chip-item--reorderable').styles(
    cursor: .grab,
    raw: const {'touch-action': 'none'},
  ),
  css('.table-edit-chip-input__chip-item--reorderable:active').styles(
    cursor: .grabbing,
  ),
  css('.table-edit-chip-input__chip-item--reorderable .z-tag__remove').styles(
    cursor: .pointer,
  ),
  css('.table-edit-chip-input__chip-item--dragging .z-tag').styles(
    opacity: 0.45,
  ),
  css('.table-edit-chip-input__drop-pipe').styles(
    position: Position.absolute(top: 3.px, bottom: 3.px),
    width: 2.px,
    radius: .all(Radius.circular(1.px)),
    backgroundColor: primaryColor,
    raw: const {'pointer-events': 'none', 'z-index': '1'},
  ),
  css('.table-edit-chip-input__drop-pipe--left').styles(
    raw: const {
      'left': '0',
      'transform': 'translate(calc(-0.5 * var(--table-edit-chip-gap) - 50%), 0)',
    },
  ),
  css(
    '.table-edit-chip-input__chip-item:first-child .table-edit-chip-input__drop-pipe--left',
  ).styles(
    raw: const {'transform': 'translate(-50%, 0)'},
  ),
  css('.table-edit-chip-input__drop-pipe--right').styles(
    raw: const {
      'right': '0',
      'transform': 'translate(calc(0.5 * var(--table-edit-chip-gap) + 50%), 0)',
    },
  ),
  css(
    '.table-edit-chip-input__chip-item:last-child .table-edit-chip-input__drop-pipe--right',
  ).styles(
    raw: const {'transform': 'translate(50%, 0)'},
  ),
  css('.table-edit-chip-input__add-row').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    alignItems: .start,
    alignSelf: .stretch,
    gap: Gap.all(ZonaiSpacing.s3),
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
    gap: Gap.all(ZonaiSpacing.s5),
    flexWrap: FlexWrap.wrap,
  ),
  css('.table-edit-boolean__label').styles(
    display: .inlineFlex,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s4),
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
    gap: Gap.all(ZonaiSpacing.s3),
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
    gap: Gap.all(ZonaiSpacing.s4),
  ),
  css('.table-edit-fk-value__input').styles(
    flex: Flex(grow: 1, shrink: 1),
    minWidth: 120.px,
  ),
  css('.table-filter-fk-value').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s4),
  ),
  css('.table-edit-enum-values--empty').styles(
    fontSize: 0.8125.rem,
    color: mutedColor,
    raw: const {'line-height': '1.4'},
  ),
];
