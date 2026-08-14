/// A tabbed code viewer.
///
/// Tab content is passed as parallel `List<String>`s rather than components
/// because `@client` parameters have to survive serialization to the browser —
/// the highlighting is re-run client-side on switch.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../code.dart';

@client
class CodeTabs extends StatefulComponent {
  const CodeTabs({
    required this.labels,
    required this.filenames,
    required this.sources,
    required this.captions,
    required this.langs,
    super.key,
  });

  final List<String> labels;
  final List<String> filenames;
  final List<String> sources;
  final List<String> captions;

  /// One [Lang] name per tab, as a string so the value survives serialization
  /// into the client bundle.
  final List<String> langs;

  @override
  State<CodeTabs> createState() => CodeTabsState();
}

class CodeTabsState extends State<CodeTabs> {
  int _active = 0;

  @override
  Component build(BuildContext context) {
    final index = _active.clamp(0, component.labels.length - 1);

    return div(classes: 'tabs', [
      div(
        classes: 'tabs-rail',
        attributes: const {'role': 'tablist'},
        [
          for (final (i, label) in component.labels.indexed)
            button(
              classes: i == index ? 'tab tab-on' : 'tab',
              onClick: () => setState(() => _active = i),
              attributes: {'role': 'tab', 'aria-selected': '${i == index}'},
              [.text(label)],
            ),
        ],
      ),

      div(classes: 'pane tabs-body', [
        div(classes: 'window-bar', [
          span(classes: 'dots', [span([]), span([]), span([])]),
          span(classes: 'window-name', [.text(component.filenames[index])]),
        ]),
        CodeBlock(
          component.sources[index],
          lang: Lang.values.firstWhere(
            (l) => l.name == component.langs[index],
            orElse: () => Lang.dart,
          ),
        ),
      ]),

      p(classes: 'tabs-caption', [.text(component.captions[index])]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.tabs', [
      css('&').styles(display: .flex, flexDirection: .column, gap: .all(14.px)),

      css('.tabs-rail').styles(
        display: .flex,
        padding: .all(4.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(11.px),
        overflow: .only(x: .auto),
        alignSelf: .start,
        gap: .all(3.px),
        backgroundColor: .rgba(255, 255, 255, 0.02),
      ),
      css('.tab').styles(
        padding: .symmetric(vertical: 8.px, horizontal: 15.px),
        border: .all(style: .none),
        radius: .circular(8.px),
        cursor: .pointer,
        transition: Transition.combine([
          Transition('color', duration: 160.ms),
          Transition('background-color', duration: 160.ms),
        ]),
        color: .variable('--fg-mute'),
        fontFamily: .variable('--sans'),
        fontSize: 13.5.px,
        fontWeight: .w600,
        whiteSpace: .noWrap,
        backgroundColor: Colors.transparent,
      ),
      css('.tab:hover').styles(color: .variable('--fg-dim')),
      css('.tab-on').styles(
        color: .variable('--void'),
        backgroundColor: .variable('--zon'),
        raw: {'box-shadow': '0 6px 18px -8px var(--zon-glow)'},
      ),
      css('.tab-on:hover').styles(color: .variable('--void')),

      css('.tabs-body').styles(
        backgroundColor: .variable('--ink'),
        raw: {'box-shadow': '0 24px 60px -28px rgba(0,0,0,0.85)'},
      ),
      css('.tabs-caption').styles(
        maxWidth: 680.px,
        color: .variable('--fg-mute'),
        fontSize: 13.5.px,
        lineHeight: 1.6.em,
      ),
    ]),
  ];
}
