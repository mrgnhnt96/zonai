import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../constants/spacing.dart';
import '../../constants/theme.dart';

/// Pill label for list values, FK previews, and similar.
///
/// When [onRemove] is set, a dismiss control is rendered inside the tag chrome.
class ZonaiTag extends StatelessComponent {
  const ZonaiTag({
    required this.label,
    this.monospace = false,
    this.onRemove,
    super.key,
  });

  final String label;
  final bool monospace;
  final void Function()? onRemove;

  @override
  Component build(BuildContext context) {
    final classes = [
      'z-tag',
      if (monospace) 'z-tag--mono',
      if (onRemove != null) 'z-tag--removable',
    ].join(' ');

    return span(classes: classes, [
      .text(label),
      if (onRemove != null)
        button(
          type: .button,
          classes: 'z-tag__remove',
          attributes: {'aria-label': 'Remove $label'},
          events: {
            'click': (event) {
              event.stopPropagation();
              onRemove!();
            },
          },
          [_tagRemoveIcon()],
        ),
    ]);
  }
}

Component _tagRemoveIcon() {
  return svg(
    viewBox: '0 0 12 12',
    width: 10.px,
    height: 10.px,
    attributes: {'aria-hidden': 'true', 'fill': 'none'},
    [
      path(
        stroke: const Color('currentColor'),
        strokeWidth: '1.5',
        d: 'M3 3l6 6M9 3 3 9',
        attributes: const {'stroke-linecap': 'round'},
        [],
      ),
    ],
  );
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
  css('.z-tag--removable').styles(
    gap: Gap.all(ZonaiSpacing.s2),
    padding: .only(
      left: ZonaiSpacing.s4,
      right: ZonaiSpacing.s2,
      top: ZonaiSpacing.s2,
      bottom: ZonaiSpacing.s2,
    ),
  ),
  css('.z-tag__remove').styles(
    width: 18.px,
    height: 18.px,
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .zero,
    border: Border.none,
    backgroundColor: Colors.transparent,
    color: mutedColor,
    cursor: .pointer,
    radius: .all(Radius.circular(4.px)),
    flex: Flex(grow: 0, shrink: 0),
    raw: const {'font': 'inherit', 'line-height': '1'},
  ),
  css('.z-tag__remove:hover').styles(
    color: fgColor,
    backgroundColor: hoverColor,
  ),
];
