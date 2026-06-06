import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../../constants/button_sizes.dart';

enum ZonaiButtonVariant { primary, secondary, ghost }

/// Themed button with primary, secondary, and ghost variants.
class ZonaiButton extends StatelessComponent {
  const ZonaiButton({
    super.key,
    required this.child,
    this.variant = ZonaiButtonVariant.primary,
    this.size,
    this.type = ButtonType.button,
    this.disabled = false,
    this.fullWidth = false,
    this.onClick,
    this.events,
    this.attributes = const {},
    this.classes = '',
  });

  final Component child;
  final ZonaiButtonVariant variant;
  final ZonaiButtonSize? size;
  final ButtonType type;
  final bool disabled;
  final bool fullWidth;
  final void Function()? onClick;
  final Map<String, void Function(web.Event)>? events;
  final Map<String, String> attributes;
  final String classes;

  String get _variantClass => switch (variant) {
    ZonaiButtonVariant.primary => 'z-btn--primary',
    ZonaiButtonVariant.secondary => 'z-btn--secondary',
    ZonaiButtonVariant.ghost => 'z-btn--ghost',
  };

  ZonaiButtonSize get _resolvedSize =>
      size ?? (variant == ZonaiButtonVariant.ghost ? ZonaiButtonSize.sm : ZonaiButtonSize.md);

  @override
  Component build(BuildContext context) {
    final classList = [
      ZonaiButtonSizes.textButtonClasses(size: _resolvedSize, variantClass: _variantClass, fullWidth: fullWidth),
      if (classes.isNotEmpty) classes,
    ].join(' ');

    return button(
      type: type,
      classes: classList,
      attributes: attributes,
      disabled: disabled,
      onClick: onClick,
      events: events,
      [child],
    );
  }
}
