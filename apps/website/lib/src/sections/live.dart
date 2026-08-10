/// Live queries — the feature most people arrive looking for, so it gets its
/// own section right after the hero.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../code.dart';
import '../interactive/stream_demo.dart';
import '../theme.dart';
import '../ui.dart';

const _listen = r'''
final sub = client.db.listen
    .list(
      body: StreamListBody(
        table: 'tasks',
        where: Eq('isComplete', false),
        limit: 50,
      ),
      fromJson: (row) => row,
    )
    .listen((tasks) {
      // Fires on connect, then again on every insert,
      // update, or delete that changes this result set.
      setState(() => _tasks = tasks);
    });

await sub.cancel();
''';

class LiveQueries extends StatelessComponent {
  const LiveQueries({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'live',
      eyebrow: 'Live queries',
      title: .fragment([.text('Stop '), accent('polling'), .text('.')]),
      lede:
          'Every table gets three streaming endpoints alongside the ordinary reads. The server holds the connection '
          'open and pushes a new payload whenever the underlying query result changes. No WebSocket setup, no pub/sub '
          'broker, no separate "realtime" product to bolt on.',
      children: [
        div(classes: 'live-grid', [
          const CodeWindow(
            filename: 'lib/widgets/task_list.dart',
            source: _listen,
            badge: 'zonai_client',
          ),
          const StreamDemo(),
        ]),

        div(classes: 'live-notes', [
          for (final (title, body) in const [
            (
              'Same rules, same limits',
              'Streams reuse canView / canList / canCount and the matching rate-limit buckets. There is no separate '
                  'canStream to forget about.',
            ),
            (
              'Three shapes',
              'stream-one for a single row, stream-list for a result set, stream-count for a running total. Pick the '
                  'one your UI actually binds to.',
            ),
            (
              'Plain HTTP underneath',
              'GET /db/stream*, JSON in a ?body= query param, events until you cancel. Reachable from anything that '
                  'speaks HTTP, not just Dart.',
            ),
          ])
            div(classes: 'live-note', [
              h3([.text(title)]),
              p([.text(body)]),
            ]),
        ]),

        docsLink('Read the streaming guide', Links.streaming),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.live-grid').styles(
      display: .grid,
      gridTemplate: gridFr([1, 1]),
      gap: .all(20.px),
      alignItems: .stretch,
    ),
    css('.live-grid > *').styles(raw: {'min-width': '0'}),

    css('.live-notes', [
      css('&').styles(
        display: .grid,
        margin: .symmetric(vertical: 40.px),
        gridTemplate: gridCols(3),
        gap: .all(28.px),
      ),
      css('.live-note').styles(padding: .only(left: 16.px), raw: {'border-left': '2px solid var(--edge-2)'}),
      css('.live-note h3').styles(
        margin: .only(bottom: 8.px),
        color: .variable('--fg'),
        fontSize: 15.px,
        fontWeight: .w600,
      ),
      css('.live-note p').styles(color: .variable('--fg-mute'), fontSize: 14.px, lineHeight: 1.6.em),
    ]),

    css.media(MediaQuery.screen(maxWidth: 980.px), [
      css('.live-grid').styles(gridTemplate: gridCols(1)),
      css('.live-notes').styles(gridTemplate: gridCols(1)),
    ]),
  ];
}
