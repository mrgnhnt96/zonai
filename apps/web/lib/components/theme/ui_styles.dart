import 'package:jaspr/dom.dart';

import '../../constants/button_sizes.dart';
import '../../constants/theme.dart';
import '../../constants/spacing.dart';
import 'zonai_boolean_check.dart';
import 'zonai_enum_chip.dart';
import 'zonai_tag.dart';

/// Shared UI class names used by theme components.
abstract final class ZonaiClasses {
  static const card = 'z-card';
  static const pageTitle = 'z-page-title';
  static const pageSubtitle = 'z-page-subtitle';
  static const errorText = 'z-error';
  static const field = 'z-field';
  static const label = 'z-label';
  static const input = 'z-input';
  static const selectWrap = 'z-select';
  static const selectNative = 'z-select__native';
  static const btn = 'z-btn';
  static const btnPrimary = 'z-btn z-btn--md z-btn--primary';
  static const btnSecondary = 'z-btn z-btn--md z-btn--secondary';
  static const btnGhost = 'z-btn z-btn--sm z-btn--ghost';
  static const btnFullWidth = 'z-btn--full';
  static const authPage = 'z-auth-page';
  static const authPageTheme = 'z-auth-page__theme';
  static const authPageBack = 'z-auth-page__back';
  static const sectionLabel = 'z-section-label';
  static const alertError = 'z-alert z-alert--error';
  static const alertTitle = 'z-alert__title';
  static const alertBody = 'z-alert__body';
  static const panel = 'z-panel';
  static const panelEmpty = 'z-panel z-panel--empty';
  static const panelTitle = 'z-panel__title';
  static const stack = 'z-stack';
  static const authLayout = 'z-auth-layout';
  static const authBrand = 'z-auth-brand';
  static const authLogo = 'z-auth-logo';
  static const authAppName = 'z-auth-app-name';
  static const authTagline = 'z-auth-tagline';
  static const authMethods = 'z-auth-methods';
  static const authMethod = 'z-auth-method';
  static const authMethodTitle = 'z-auth-method__title';
  static const authMethodDesc = 'z-auth-method__desc';
  static const authActions = 'z-auth-actions';
  static const authFooter = 'z-auth-footer';
  static const authLink = 'z-auth-link';
  static const authSentIcon = 'z-auth-sent';
}

@css
List<StyleRule> get zonaiUiStyles => [
  css('.z-card').styles(
    width: 100.percent,
    maxWidth: 420.px,
    backgroundColor: surfaceColor,
    padding: .all(ZonaiSpacing.s14),
    radius: .all(Radius.circular(20.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': 'var(--zonai-shadow)'},
  ),
  css('.z-page-title').styles(
    margin: .only(bottom: ZonaiSpacing.s4),
    fontSize: 1.625.rem,
    fontWeight: .w600,
    raw: const {'letter-spacing': '-0.02em', 'line-height': '1.25'},
  ),
  css('.z-page-subtitle').styles(
    margin: .only(bottom: ZonaiSpacing.s12),
    fontSize: 0.9375.rem,
    color: mutedColor,
    raw: const {'line-height': '1.5'},
  ),
  css('.z-error').styles(
    margin: .only(bottom: ZonaiSpacing.s8),
    fontSize: 0.875.rem,
    color: errorColor,
    raw: const {'line-height': '1.45'},
  ),
  css('.z-field').styles(margin: .only(bottom: ZonaiSpacing.s10)),
  css('.z-label').styles(
    display: .block,
    margin: .only(bottom: ZonaiSpacing.s4),
    fontSize: 0.8125.rem,
    fontWeight: .w600,
    letterSpacing: 0.01.rem,
    color: fgColor,
  ),
  css('.z-input').styles(
    display: .block,
    width: 100.percent,
    padding: .symmetric(horizontal: ZonaiSpacing.s7, vertical: ZonaiSpacing.s5_5),
    radius: .all(Radius.circular(10.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    color: fgColor,
    fontSize: 0.9375.rem,
    outline: Outline(style: OutlineStyle.none),
    raw: const {
      'font': 'inherit',
      'line-height': '1.4',
      'transition': 'border-color 0.15s ease, box-shadow 0.15s ease',
    },
  ),
  css('.z-input:hover:not(:disabled)').styles(
    border: .all(color: mutedColor, width: 1.px, style: .solid),
  ),
  css('.z-input:focus-visible').styles(
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'},
  ),
  css('.z-input:disabled').styles(opacity: 0.6, cursor: .notAllowed, backgroundColor: hoverColor),
  css('textarea.z-input').styles(raw: const {'resize': 'vertical'}),
  css('.z-select').styles(position: Position.relative(), display: .block, width: 100.percent, minWidth: .zero),
  css('.z-select__native').styles(
    display: .block,
    width: 100.percent,
    padding: .only(right: ZonaiSpacing.s14, left: ZonaiSpacing.s7, top: ZonaiSpacing.s5_5, bottom: ZonaiSpacing.s5_5),
    radius: .all(Radius.circular(10.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    color: fgColor,
    fontSize: 0.9375.rem,
    outline: Outline(style: OutlineStyle.none),
    cursor: .pointer,
    raw: const {
      'font': 'inherit',
      'line-height': '1.4',
      'appearance': 'none',
      '-webkit-appearance': 'none',
      'transition': 'border-color 0.15s ease, box-shadow 0.15s ease',
    },
  ),
  css('.z-select__native:hover:not(:disabled)').styles(
    border: .all(color: mutedColor, width: 1.px, style: .solid),
  ),
  css('.z-select__native:focus-visible').styles(
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'},
  ),
  css('.z-select__native:disabled').styles(opacity: 0.6, cursor: .notAllowed, backgroundColor: hoverColor),
  css('.z-select__chevron').styles(
    position: Position.absolute(top: 0.px, right: 12.px, bottom: 0.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    color: mutedColor,
    pointerEvents: PointerEvents.none,
  ),
  css('.z-select:focus-within .z-select__chevron').styles(color: fgColor),
  css('.z-btn').styles(
    display: .inlineFlex,
    alignItems: .center,
    justifyContent: .center,
    gap: Gap.all(ZonaiSpacing.s4),
    cursor: .pointer,
    border: Border.none,
    fontWeight: .w600,
    outline: Outline(style: OutlineStyle.none),
    raw: const {
      'font': 'inherit',
      'line-height': '1.2',
      'transition':
          'background-color 0.15s ease, color 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease, opacity 0.15s ease',
    },
  ),
  css('.z-btn--md').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.md),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.md),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.md))),
  ),
  css('.z-btn--sm').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.sm),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.sm),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.sm))),
  ),
  css('.z-btn--xs').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.xs),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.xs),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.xs))),
  ),
  css('.z-btn--xxs').styles(
    padding: ZonaiButtonSizes.textPadding(ZonaiButtonSize.xxs),
    fontSize: ZonaiButtonSizes.textFontSize(ZonaiButtonSize.xxs),
    radius: .all(Radius.circular(ZonaiButtonSizes.textRadius(ZonaiButtonSize.xxs))),
  ),
  css('.z-btn--full').styles(width: 100.percent),
  css('.z-btn--primary').styles(
    color: onPrimaryColor,
    backgroundColor: primaryColor,
    raw: const {'box-shadow': '0 1px 2px rgb(0 0 0 / 0.06)'},
  ),
  css('.z-btn--primary:hover:not(:disabled)').styles(backgroundColor: primaryHoverColor),
  css(
    '.z-btn--primary:focus-visible',
  ).styles(raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring), 0 1px 2px rgb(0 0 0 / 0.06)'}),
  css('.z-btn--secondary').styles(
    color: fgColor,
    backgroundColor: surfaceColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
  ),
  css('.z-btn--secondary:hover:not(:disabled)').styles(
    backgroundColor: hoverColor,
    border: .all(color: mutedColor, width: 1.px, style: .solid),
  ),
  css('.z-btn--secondary:focus-visible').styles(raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'}),
  css('.z-btn--ghost').styles(
    color: mutedColor,
    backgroundColor: surfaceColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
  ),
  css('.z-btn--ghost:hover:not(:disabled)').styles(backgroundColor: hoverColor, color: fgColor),
  css('.z-btn--ghost:focus-visible').styles(raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'}),
  css('.z-btn:disabled').styles(opacity: 0.55, cursor: .notAllowed),
  css('.z-btn + .z-btn').styles(margin: .only(top: ZonaiSpacing.s5)),
  css('.z-icon-btn').styles(
    display: .inlineFlex,
    alignItems: .center,
    justifyContent: .center,
    padding: .zero,
    cursor: .pointer,
    border: Border.none,
    outline: Outline(style: OutlineStyle.none),
    flex: Flex(grow: 0, shrink: 0),
    raw: const {
      'font': 'inherit',
      'line-height': '1',
      'transition': 'background-color 0.15s ease, color 0.15s ease, border-color 0.15s ease, opacity 0.15s ease',
    },
  ),
  css('.z-icon-btn--lg').styles(
    width: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.lg),
    height: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.lg),
    fontSize: ZonaiButtonSizes.iconFontSize(ZonaiIconButtonSize.lg),
    radius: .all(Radius.circular(ZonaiButtonSizes.iconRadius(ZonaiIconButtonSize.lg))),
  ),
  css('.z-icon-btn--md').styles(
    width: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.md),
    height: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.md),
    fontSize: ZonaiButtonSizes.iconFontSize(ZonaiIconButtonSize.md),
    radius: .all(Radius.circular(ZonaiButtonSizes.iconRadius(ZonaiIconButtonSize.md))),
  ),
  css('.z-icon-btn--sm').styles(
    width: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.sm),
    height: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.sm),
    fontSize: ZonaiButtonSizes.iconFontSize(ZonaiIconButtonSize.sm),
    radius: .all(Radius.circular(ZonaiButtonSizes.iconRadius(ZonaiIconButtonSize.sm))),
  ),
  css('.z-icon-btn--xs').styles(
    width: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.xs),
    height: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.xs),
    fontSize: ZonaiButtonSizes.iconFontSize(ZonaiIconButtonSize.xs),
    radius: .all(Radius.circular(ZonaiButtonSizes.iconRadius(ZonaiIconButtonSize.xs))),
  ),
  css('.z-icon-btn--xxs').styles(
    width: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.xxs),
    height: ZonaiButtonSizes.iconDimension(ZonaiIconButtonSize.xxs),
    fontSize: ZonaiButtonSizes.iconFontSize(ZonaiIconButtonSize.xxs),
    radius: .all(Radius.circular(ZonaiButtonSizes.iconRadius(ZonaiIconButtonSize.xxs))),
  ),
  css('.z-icon-btn--bordered').styles(
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: surfaceColor,
    color: mutedColor,
  ),
  css('.z-icon-btn--bordered:hover:not(:disabled)').styles(
    backgroundColor: hoverColor,
    color: fgColor,
    border: .all(color: mutedColor, width: 1.px, style: .solid),
  ),
  css('.z-icon-btn--ghost').styles(backgroundColor: Colors.transparent, color: mutedColor),
  css('.z-icon-btn--ghost:hover:not(:disabled)').styles(backgroundColor: hoverColor, color: fgColor),
  css('.z-icon-btn:disabled').styles(opacity: 0.55, cursor: .notAllowed),
  css('.z-icon-btn:focus-visible').styles(raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'}),
  css('.z-auth-page').styles(
    flex: Flex(grow: 1, shrink: 0),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .all(ZonaiSpacing.s13),
    position: Position.relative(),
    raw: const {'background': 'radial-gradient(ellipse 80% 60% at 50% -20%, var(--zonai-glow), transparent)'},
  ),
  css('.z-auth-page__theme').styles(
    position: Position.absolute(top: 24.px, right: 24.px),
  ),
  css('.z-auth-page__back').styles(
    position: Position.absolute(top: 24.px, left: 24.px),
  ),
  css('.z-auth-layout').styles(
    width: 100.percent,
    maxWidth: 440.px,
    display: .flex,
    flexDirection: FlexDirection.column,
    alignItems: .stretch,
    gap: Gap.all(ZonaiSpacing.s11),
  ),
  css('.z-auth-brand').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    alignItems: .center,
    gap: Gap.all(ZonaiSpacing.s5),
    textAlign: .center,
  ),
  css('.z-auth-logo').styles(
    width: 52.px,
    height: 52.px,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    radius: .all(Radius.circular(14.px)),
    backgroundColor: primaryColor,
    color: onPrimaryColor,
    fontSize: 1.375.rem,
    fontWeight: .w700,
    raw: const {'box-shadow': '0 8px 24px -6px var(--zonai-focus-ring)'},
  ),
  css(
    '.z-auth-app-name',
  ).styles(margin: .zero, fontSize: 1.25.rem, fontWeight: .w600, raw: const {'letter-spacing': '-0.02em'}),
  css('.z-auth-tagline').styles(margin: .zero, fontSize: 0.875.rem, color: mutedColor),
  css(
    '.z-auth-methods',
  ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s5), width: 100.percent),
  css('.z-auth-method').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    alignItems: .start,
    gap: Gap.all(ZonaiSpacing.s2),
    width: 100.percent,
    padding: .all(ZonaiSpacing.s8),
    cursor: .pointer,
    textAlign: .left,
    radius: .all(Radius.circular(12.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    backgroundColor: bgColor,
    raw: const {
      'font': 'inherit',
      'transition': 'border-color 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease',
    },
  ),
  css('.z-auth-method:hover').styles(
    backgroundColor: hoverColor,
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'},
  ),
  css('.z-auth-method__title').styles(fontSize: 0.9375.rem, fontWeight: .w600, color: fgColor),
  css('.z-auth-method__desc').styles(fontSize: 0.8125.rem, color: mutedColor, raw: const {'line-height': '1.4'}),
  css('.z-auth-actions').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s5),
    margin: .only(top: ZonaiSpacing.s2),
  ),
  css('.z-auth-footer').styles(
    margin: .only(top: ZonaiSpacing.s2),
    textAlign: .center,
  ),
  css('.z-auth-link').styles(
    padding: .symmetric(vertical: ZonaiSpacing.s4),
    cursor: .pointer,
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: primaryColor,
    fontSize: 0.875.rem,
    fontWeight: .w600,
    raw: const {'font': 'inherit', 'text-decoration': 'underline', 'text-underline-offset': '3px'},
  ),
  css('.z-auth-link:hover').styles(color: primaryHoverColor),
  css('.z-auth-sent').styles(
    width: 48.px,
    height: 48.px,
    margin: .only(bottom: ZonaiSpacing.s4),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    radius: .all(Radius.circular(12.px)),
    backgroundColor: selectedBgColor,
    color: primaryColor,
    fontSize: 1.5.rem,
    raw: const {'align-self': 'center'},
  ),
  css('.z-section-label').styles(
    fontSize: 0.6875.rem,
    fontWeight: .w600,
    letterSpacing: 0.06.rem,
    color: mutedColor,
    textTransform: .upperCase,
  ),
  css('.z-stack').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s5)),
  css('.z-alert').styles(
    padding: .all(ZonaiSpacing.s8),
    radius: .all(Radius.circular(12.px)),
    border: .all(color: errorBorderColor, width: 1.px, style: .solid),
    backgroundColor: errorBgColor,
  ),
  css('.z-alert__title').styles(
    margin: .only(bottom: ZonaiSpacing.s4),
    fontSize: 0.9375.rem,
    fontWeight: .w600,
    color: errorColor,
  ),
  css('.z-alert__body').styles(
    margin: .zero,
    fontSize: 0.8125.rem,
    color: errorFgColor,
    raw: const {
      'line-height': '1.45',
      'white-space': 'pre-wrap',
      'overflow-wrap': 'anywhere',
      'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    },
  ),
  css('.z-panel').styles(
    flex: Flex(grow: 1, shrink: 1),
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s6),
    minHeight: .zero,
    overflow: Overflow.hidden,
    padding: .all(ZonaiSpacing.s11),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    radius: .all(Radius.circular(16.px)),
    backgroundColor: surfaceColor,
    raw: const {'box-shadow': 'var(--zonai-shadow-sm)'},
  ),
  css('.z-panel--empty').styles(alignItems: .center, justifyContent: .center, padding: .all(ZonaiSpacing.s15)),
  css(
    '.z-panel__title',
  ).styles(margin: .zero, fontSize: 1.375.rem, fontWeight: .w600, raw: const {'letter-spacing': '-0.02em'}),
  ...zonaiTagStyles,
  ...zonaiEnumChipStyles,
  ...zonaiBooleanCheckStyles,
];
