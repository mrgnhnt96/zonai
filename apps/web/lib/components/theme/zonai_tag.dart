import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/spacing.dart';
import '../../constants/theme.dart';

/// Read-only pill label for list values, FK previews, and similar.
class ZonaiTag extends StatelessComponent {
  const ZonaiTag({required this.label, this.monospace = false, super.key});

  final String label;
  final bool monospace;

  @override
  Component build(BuildContext context) {
    final classes = [
      'z-tag',
      if (monospace) 'z-tag--mono',
    ].join(' ');

    return span(classes: classes, [.text(label)]);
  }
}

/// Horizontal wrap of [ZonaiTag] labels.
class ZonaiTagList extends StatelessComponent {
  const ZonaiTagList({required this.tags, this.monospace = false, super.key});

  final List<String> tags;
  final bool monospace;

  @override
  Component build(BuildContext context) {
    if (tags.isEmpty) return Component.empty();

    return div(
      classes: 'z-tag-list',
      [
        for (final tag in tags) ZonaiTag(label: tag, monospace: monospace),
      ],
    );
  }
}

@css
List<StyleRule> get zonaiTagStyles => [
  css('.z-tag-list').styles(
    display: .flex,
    flexDirection: FlexDirection.row,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(ZonaiSpacing.s3),
  ),
  css('.z-tag').styles(
    display: .inlineFlex,
    alignItems: .center,
    padding: .symmetric(horizontal: ZonaiSpacing.s4, vertical: ZonaiSpacing.s2),
    radius: .all(Radius.circular(6.px)),
    backgroundColor: selectedBgColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    fontSize: 0.8125.rem,
    raw: const {'line-height': '1.35'},
  ),
  css('.z-tag--mono').styles(
    raw: const {'font-family': 'ui-monospace, monospace'},
  ),
];
