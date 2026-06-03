import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'ui_styles.dart';

enum ZonaiButtonVariant { primary, secondary, ghost }

/// Themed button with primary, secondary, and ghost variants.
class ZonaiButton extends StatelessComponent {
  const ZonaiButton({
    super.key,
    required this.child,
    this.variant = ZonaiButtonVariant.primary,
    this.type = ButtonType.button,
    this.disabled = false,
    this.fullWidth = false,
    this.onClick,
    this.attributes = const {},
  });

  final Component child;
  final ZonaiButtonVariant variant;
  final ButtonType type;
  final bool disabled;
  final bool fullWidth;
  final void Function()? onClick;
  final Map<String, String> attributes;

  String get _variantClass => switch (variant) {
    ZonaiButtonVariant.primary => ZonaiClasses.btnPrimary,
    ZonaiButtonVariant.secondary => ZonaiClasses.btnSecondary,
    ZonaiButtonVariant.ghost => ZonaiClasses.btnGhost,
  };

  @override
  Component build(BuildContext context) {
    final classes = [
      _variantClass,
      if (fullWidth) ZonaiClasses.btnFullWidth,
    ].join(' ');

    return button(
      type: type,
      classes: classes,
      attributes: attributes,
      disabled: disabled,
      onClick: onClick,
      [child],
    );
  }
}
