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
  css('.table-edit-chip-input__chip-item--dragging-pointer .z-tag').styles(
    visibility: .hidden,
  ),
  css('.table-edit-chip-input__drag-ghost.z-tag').styles(
    position: Position.fixed(),
    radius: .all(Radius.circular(6.px)),
    overflow: Overflow.visible,
    raw: const {
      'z-index': '10000',
      'pointer-events': 'none',
      'margin': '0',
      'opacity': '0.95',
      'box-shadow': '0 2px 8px rgba(0, 0, 0, 0.18)',
      'background-clip': 'padding-box',
      '-webkit-background-clip': 'padding-box',
    },
  ),
  css('.table-edit-chip-input__drag-ghost .z-tag__remove').styles(
    display: .none,
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
  css('.table-edit-chip-input__drop-pipe--right').styles(
    raw: const {
      'right': '0',
      'transform': 'translate(calc(0.5 * var(--table-edit-chip-gap) + 50%), 0)',
    },
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
  css('.table-edit-fk-value__input--invalid').styles(
    raw: const {'border-color': 'var(--zonai-error)'},
  ),
  css('.table-edit-fk-value__error').styles(
    width: 100.percent,
    margin: .zero,
    fontSize: 0.8125.rem,
    color: errorColor,
    raw: const {'line-height': '1.45'},
  ),
  css('.table-edit-fk-value__hint').styles(
    fontSize: 0.8125.rem,
    color: mutedColor,
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
  css('.table-edit-password-field').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s4),
  ),
  css('.table-edit-password-field input').styles(
    flex: Flex(grow: 1, shrink: 1),
    minWidth: 120.px,
  ),
  css('.table-edit-password-field__icon').styles(
    width: 1.em,
    height: 1.em,
    display: .block,
  ),
  css('.table-edit-photo-field').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s4),
    width: 100.percent,
  ),
  css('.table-edit-photo-field__thumbs').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(ZonaiSpacing.s3),
  ),
  css('.table-edit-photo-field__thumbs--active .table-edit-photo-field__thumb').styles(
    border: Border.all(color: primaryColor, width: 1.px),
    backgroundColor: selectedBgColor,
  ),
  css('.table-edit-photo-field__thumb').styles(
    position: Position.relative(),
    width: 72.px,
    height: 72.px,
    radius: .all(Radius.circular(6.px)),
    overflow: Overflow.hidden,
    border: Border.all(color: borderColor, width: 1.px),
  ),
  css('.table-edit-photo-field__thumb img').styles(
    width: 100.percent,
    height: 100.percent,
    raw: const {'object-fit': 'cover', 'display': 'block'},
  ),
  css('.table-edit-photo-field__thumb-placeholder').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    width: 100.percent,
    height: 100.percent,
    fontSize: 0.625.rem,
    color: mutedColor,
    padding: .all(4.px),
    raw: const {'word-break': 'break-all', 'text-align': 'center'},
  ),
  css('.table-edit-photo-field__remove').styles(
    position: Position.absolute(top: 2.px, right: 2.px),
    width: 20.px,
    height: 20.px,
    padding: .zero,
    border: Border.unset,
    radius: .all(Radius.circular(10.px)),
    backgroundColor: const Color('#0009'),
    color: const Color('#fff'),
    fontSize: 0.875.rem,
    cursor: .pointer,
    raw: const {'line-height': '1'},
  ),
  css('.table-edit-photo-field__zone').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s3),
    padding: .symmetric(vertical: 16.px, horizontal: 12.px),
    border: Border.all(color: borderColor, width: 1.px, style: BorderStyle.dashed),
    radius: .all(Radius.circular(6.px)),
    backgroundColor: hoverColor,
  ),
  css('.table-edit-photo-field__zone--active').styles(
    border: Border.all(color: primaryColor, width: 1.px, style: BorderStyle.dashed),
    backgroundColor: selectedBgColor,
  ),
  css('.table-edit-photo-field__zone--disabled').styles(
    opacity: 0.6,
    pointerEvents: .none,
  ),
  css('.table-edit-photo-field__hint').styles(
    margin: .zero,
    fontSize: 0.8125.rem,
    color: mutedColor,
    textAlign: TextAlign.center,
  ),
  css('.table-edit-photo-field__error').styles(
    margin: .zero,
    fontSize: 0.8125.rem,
    color: errorColor,
  ),
];
