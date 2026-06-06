import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../../constants/button_sizes.dart';

/// Themed square icon button with shared size and variant tokens.
class ZonaiIconButton extends StatelessComponent {
  const ZonaiIconButton({
    super.key,
    required this.child,
    this.size = ZonaiIconButtonSize.sm,
    this.variant = ZonaiIconButtonVariant.bordered,
    this.type = ButtonType.button,
    this.disabled = false,
    this.onClick,
    this.events,
    this.attributes = const {},
    this.classes = '',
  });

  final Component child;
  final ZonaiIconButtonSize size;
  final ZonaiIconButtonVariant variant;
  final ButtonType type;
  final bool disabled;
  final void Function()? onClick;
  final Map<String, void Function(web.Event)>? events;
  final Map<String, String> attributes;
  final String classes;

  @override
  Component build(BuildContext context) {
    return button(
      type: type,
      classes: ZonaiButtonSizes.iconButtonClasses(size: size, variant: variant, extra: classes),
      attributes: attributes,
      disabled: disabled,
      onClick: onClick,
      events: events,
      [child],
    );
  }
}
