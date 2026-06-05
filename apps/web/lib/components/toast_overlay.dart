import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../constants/button_sizes.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/toast_provider.dart';
import 'theme/zonai_icon_button.dart';

/// Fixed-position toast stack rendered at the app shell level.
class ToastOverlay extends StatelessComponent {
  const ToastOverlay({super.key});

  @override
  Component build(BuildContext context) {
    final toast = context.watch(toastProvider);
    if (toast == null) {
      return Component.empty();
    }

    void dismiss() => context.read(toastProvider.notifier).dismiss();
    final variantClass = switch (toast.variant) {
      ToastVariant.error => 'zonai-toast--error',
      ToastVariant.success => 'zonai-toast--success',
    };

    return div(classes: 'zonai-toast-host', [
      div(
        classes: 'zonai-toast $variantClass',
        attributes: {'role': 'alert'},
        [
          span(classes: 'zonai-toast__text', [.text(toast.text)]),
          ZonaiIconButton(
            size: ZonaiIconButtonSize.xs,
            variant: ZonaiIconButtonVariant.ghost,
            classes: 'zonai-toast__dismiss',
            attributes: {'aria-label': 'Dismiss'},
            onClick: dismiss,
            child: .text('×'),
          ),
        ],
      ),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.zonai-toast-host').styles(
      position: Position.fixed(left: 0.px, right: 0.px, bottom: 24.px),
      display: .flex,
      justifyContent: .center,
      padding: .symmetric(horizontal: ZonaiSpacing.s8),
      pointerEvents: .none,
      raw: const {'z-index': '300'},
    ),
    css('.zonai-toast').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      gap: Gap.all(ZonaiSpacing.s6),
      maxWidth: 32.rem,
      padding: .symmetric(horizontal: ZonaiSpacing.s8, vertical: ZonaiSpacing.s6),
      radius: .all(Radius.circular(12.px)),
      pointerEvents: .auto,
      raw: const {
        'width': 'fit-content',
        'box-shadow': 'var(--zonai-shadow)',
        'animation': 'zonai-toast-in 0.2s ease-out',
      },
    ),
    css('.zonai-toast--error').styles(
      border: .all(color: errorBorderColor, width: 1.px, style: .solid),
      backgroundColor: errorBgColor,
    ),
    css('.zonai-toast--success').styles(
      border: .all(color: successBorderColor, width: 1.px, style: .solid),
      backgroundColor: successBgColor,
    ),
    css('.zonai-toast--error .zonai-toast__text').styles(color: errorFgColor),
    css('.zonai-toast--success .zonai-toast__text').styles(color: successFgColor),
    css('.zonai-toast__text').styles(
      flex: Flex(grow: 1, shrink: 1),
      minWidth: .zero,
      margin: .zero,
      fontSize: 0.875.rem,
      fontWeight: .w500,
      textAlign: .left,
      raw: const {
        'line-height': '1.45',
        'overflow-wrap': 'anywhere',
      },
    ),
    css('.zonai-toast--error .zonai-toast__dismiss').styles(color: errorColor),
    css('.zonai-toast--success .zonai-toast__dismiss').styles(color: successColor),
    css('.zonai-toast__dismiss').styles(flex: Flex(grow: 0, shrink: 0), margin: .zero),
    css('.zonai-toast--error .zonai-toast__dismiss:hover').styles(backgroundColor: errorBorderColor),
    css('.zonai-toast--success .zonai-toast__dismiss:hover').styles(backgroundColor: successBorderColor),
    css('@keyframes zonai-toast-in').styles(
      raw: const {
        'from': '{ opacity: 0; transform: translateY(8px); }',
        'to': '{ opacity: 1; transform: translateY(0); }',
      },
    ),
  ];
}
