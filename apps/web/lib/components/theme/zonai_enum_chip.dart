import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/spacing.dart';
import '../../constants/theme.dart';

/// Read-only enum value pill (selected appearance).
class ZonaiEnumChip extends StatelessComponent {
  const ZonaiEnumChip({required this.label, super.key});

  final String label;

  @override
  Component build(BuildContext context) {
    return span(classes: 'z-enum-chip z-enum-chip--selected', [.text(label)]);
  }
}

/// Read-only row of enum chips for one or more values.
class ZonaiEnumChipRow extends StatelessComponent {
  const ZonaiEnumChipRow({required this.values, super.key});

  final List<String> values;

  @override
  Component build(BuildContext context) {
    if (values.isEmpty) return Component.empty();

    return div(
      classes: 'z-enum-chip-row',
      [for (final value in values) ZonaiEnumChip(label: value)],
    );
  }
}

@css
List<StyleRule> get zonaiEnumChipStyles => [
  css('.z-enum-chip-row').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(ZonaiSpacing.s3),
  ),
  css('.z-enum-chip').styles(
    display: .inlineFlex,
    alignItems: .center,
    padding: .symmetric(horizontal: ZonaiSpacing.s5, vertical: ZonaiSpacing.s2_5),
    fontSize: 0.8125.rem,
    radius: .all(Radius.circular(100.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    color: fgColor,
    raw: const {'line-height': '1.3'},
  ),
  css('.z-enum-chip--selected').styles(
    backgroundColor: primaryColor,
    border: .all(color: primaryColor, width: 1.px, style: .solid),
    color: onPrimaryColor,
    fontWeight: .w600,
  ),
];
