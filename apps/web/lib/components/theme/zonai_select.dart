import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'ui_styles.dart';

final class ZonaiSelectOption {
  const ZonaiSelectOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Themed native select matching [ZonaiClasses.input] styling.
class ZonaiSelect extends StatelessComponent {
  const ZonaiSelect({
    super.key,
    required this.id,
    required this.value,
    required this.options,
    required this.onChange,
    this.placeholder,
    this.disabled = false,
    this.labelId,
  });

  final String id;
  final String value;
  final List<ZonaiSelectOption> options;
  final void Function(String value) onChange;
  final String? placeholder;
  final bool disabled;
  final String? labelId;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.selectWrap, [
      select(
        id: id,
        classes: ZonaiClasses.selectNative,
        attributes: {if (labelId != null) 'aria-labelledby': labelId!, 'autocomplete': 'off'},
        value: value,
        disabled: disabled,
        onChange: (values) => onChange(values.isEmpty ? '' : values.last),
        [
          if (placeholder != null) option(value: '', attributes: {'disabled': '', 'hidden': ''}, [.text(placeholder!)]),
          for (final opt in options) option(value: opt.value, [.text(opt.label)]),
        ],
      ),
      _chevronIcon(),
    ]);
  }
}

Component _chevronIcon() {
  return span(classes: 'z-select__chevron', [
    svg(
      viewBox: '0 0 16 16',
      width: 14.px,
      height: 14.px,
      attributes: {'aria-hidden': 'true', 'fill': 'none'},
      [
        path(
          stroke: const Color('currentColor'),
          strokeWidth: '1.5',
          d: 'M4 6l4 4 4-4',
          attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
          [],
        ),
      ],
    ),
  ]);
}
