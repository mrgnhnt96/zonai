import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/theme.dart';

/// Read-only boolean indicator: check when [checked], X when false.
class ZonaiBooleanCheck extends StatelessComponent {
  const ZonaiBooleanCheck({required this.checked, super.key});

  final bool checked;

  @override
  Component build(BuildContext context) {
    return span(
      classes: checked ? 'z-boolean-check' : 'z-boolean-check z-boolean-check--false',
      attributes: {'aria-label': checked ? 'Yes' : 'No'},
      [checked ? _checkIconSvg() : _xIconSvg()],
    );
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

Component _xIconSvg() {
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
        d: 'M4.5 4.5 11.5 11.5',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '2',
        d: 'M11.5 4.5 4.5 11.5',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
}

@css
List<StyleRule> get zonaiBooleanCheckStyles => [
  css('.z-boolean-check').styles(display: .inlineFlex, alignItems: .center, color: primaryColor),
  css('.z-boolean-check--false').styles(color: errorColor),
  css('.z-boolean-check__icon').styles(display: .block),
];
