import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/theme.dart';

/// Read-only boolean indicator: check icon when [checked], empty when false.
class ZonaiBooleanCheck extends StatelessComponent {
  const ZonaiBooleanCheck({required this.checked, super.key});

  final bool checked;

  @override
  Component build(BuildContext context) {
    if (!checked) return Component.empty();

    return span(classes: 'z-boolean-check', [_checkIconSvg()]);
  }
}

Component _checkIconSvg() {
  return svg(
    viewBox: '0 0 16 16',
    width: 16.px,
    height: 16.px,
    classes: 'z-boolean-check__icon',
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '2',
        d: 'M3.5 8.5 6.5 11.5 12.5 4.5',
        attributes: const {'stroke-linecap': 'round', 'stroke-linejoin': 'round'},
        [],
      ),
    ],
  );
}

@css
List<StyleRule> get zonaiBooleanCheckStyles => [
  css('.z-boolean-check').styles(
    display: .inlineFlex,
    alignItems: .center,
    color: primaryColor,
  ),
  css('.z-boolean-check__icon').styles(display: .block),
];
