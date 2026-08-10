/// A simulated `client.db.listen.list(...)` subscription.
///
/// This is a dramatisation, not a live connection — it mutates a local list on
/// a timer so the page can show what a pushed update *feels* like without
/// shipping a backend. Rows flash when they change and the count follows along.
library;

import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class _Row {
  _Row(this.id, this.title, {this.done = false, this.flash = false});

  final String id;
  final String title;
  bool done;
  bool flash;
}

const _seed = [
  ('tk_9f2a', 'Ship the migration', false),
  ('tk_4c81', 'Review auth rules', false),
  ('tk_7b30', 'Wire up SMTP', true),
];

const _incoming = [
  ('tk_a15e', 'Add stream endpoint'),
  ('tk_c07d', 'Backfill created_at'),
  ('tk_2d64', 'Tune rate limits'),
];

@client
class StreamDemo extends StatefulComponent {
  const StreamDemo({super.key});

  @override
  State<StreamDemo> createState() => StreamDemoState();
}

class StreamDemoState extends State<StreamDemo> {
  final _rows = [for (final (id, title, done) in _seed) _Row(id, title, done: done)];
  int _step = 0;
  int _events = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;

    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Cycles insert → toggle → delete so every kind of change is represented.
  void _tick() {
    setState(() {
      for (final row in _rows) {
        row.flash = false;
      }

      switch (_step % 4) {
        case 0 || 2:
          final (id, title) = _incoming[(_step ~/ 2) % _incoming.length];
          _rows.insert(0, _Row(id, title, flash: true));
        case 1:
          final target = _rows.lastWhere((r) => !r.done, orElse: () => _rows.last);
          target
            ..done = !target.done
            ..flash = true;
        case 3:
          if (_rows.length > 3) _rows.removeLast();
      }

      if (_rows.length > 5) _rows.removeLast();
      _step += 1;
      _events += 1;
    });
  }

  @override
  Component build(BuildContext context) {
    final open = _rows.where((r) => !r.done).length;

    return div(classes: 'pane demo', [
      div(classes: 'demo-bar', [
        span(classes: 'demo-live', [span(classes: 'demo-dot', []), .text('streaming')]),
        code(classes: 'demo-route', [.text('GET /db/stream/list')]),
        span(classes: 'demo-events', [.text('$_events pushed')]),
      ]),

      ul(classes: 'demo-rows', [
        for (final row in _rows)
          li(key: ValueKey(row.id), classes: row.flash ? 'demo-row demo-row-flash' : 'demo-row', [
            span(classes: row.done ? 'demo-check demo-check-on' : 'demo-check', []),
            span(classes: row.done ? 'demo-title demo-title-done' : 'demo-title', [.text(row.title)]),
            code(classes: 'demo-id', [.text(row.id)]),
          ]),
      ]),

      div(classes: 'demo-foot', [
        span([.text('open tasks')]),
        span(classes: 'demo-count', [.text('$open')]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.demo', [
      css('&').styles(
        display: .flex,
        flexDirection: .column,
        backgroundColor: .variable('--ink'),
        raw: {'box-shadow': '0 24px 60px -28px rgba(0,0,0,0.85)'},
      ),

      css('.demo-bar').styles(
        display: .flex,
        padding: .symmetric(vertical: 10.px, horizontal: 14.px),
        alignItems: .center,
        gap: .all(12.px),
        fontFamily: .variable('--mono'),
        fontSize: 11.5.px,
        backgroundColor: .variable('--slab'),
        raw: {'border-bottom': '1px solid var(--edge)'},
      ),
      css('.demo-live').styles(
        display: .inlineFlex,
        alignItems: .center,
        gap: .all(6.px),
        color: .variable('--zon'),
      ),
      css('.demo-dot').styles(
        width: 6.px,
        height: 6.px,
        radius: .circular(50.percent),
        animation: Animation(name: 'pulse-fade', duration: 1400.ms, curve: .easeInOut),
        backgroundColor: .variable('--zon'),
        raw: {'box-shadow': '0 0 8px var(--zon)', 'animation-iteration-count': 'infinite'},
      ),
      css('.demo-route').styles(color: .variable('--fg-mute')),
      css('.demo-events').styles(color: .variable('--fg-mute'), raw: {'margin-left': 'auto'}),

      css('.demo-rows').styles(
        display: .flex,
        minHeight: 196.px,
        margin: .zero,
        padding: .all(8.px),
        flexDirection: .column,
        gap: .all(4.px),
        listStyle: .none,
      ),
      css('.demo-row').styles(
        display: .flex,
        padding: .symmetric(vertical: 9.px, horizontal: 12.px),
        radius: .circular(8.px),
        animation: Animation(name: 'demo-in', duration: 320.ms, curve: .easeOut),
        alignItems: .center,
        gap: .all(11.px),
        fontSize: 13.5.px,
        backgroundColor: .rgba(255, 255, 255, 0.02),
      ),
      css('.demo-row-flash').styles(
        animation: Animation(name: 'demo-flash', duration: 1100.ms, curve: .easeOut),
      ),
      css('.demo-check').styles(
        width: 15.px,
        height: 15.px,
        border: .all(color: .variable('--edge-2'), width: 1.5.px),
        radius: .circular(4.px),
        transition: Transition('all', duration: 200.ms),
        raw: {'flex': '0 0 auto'},
      ),
      css('.demo-check-on').styles(
        backgroundColor: .variable('--zon'),
        raw: {
          'border-color': 'var(--zon)',
          'background-image':
              "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'%3E%3Cpath d='M2.5 6.2l2.3 2.3 4.7-5' fill='none' stroke='%2305080A' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E\")",
          'background-size': '11px',
          'background-position': 'center',
          'background-repeat': 'no-repeat',
        },
      ),
      css('.demo-title').styles(color: .variable('--fg'), raw: {'flex': '1 1 auto'}),
      css('.demo-title-done').styles(
        color: .variable('--fg-mute'),
        textDecoration: TextDecoration(line: .lineThrough),
      ),
      css('.demo-id').styles(
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 11.px,
      ),

      css('.demo-foot').styles(
        display: .flex,
        padding: .symmetric(vertical: 12.px, horizontal: 16.px),
        alignItems: .center,
        justifyContent: .spaceBetween,
        color: .variable('--fg-mute'),
        fontFamily: .variable('--mono'),
        fontSize: 12.px,
        backgroundColor: .rgba(255, 255, 255, 0.02),
        raw: {'border-top': '1px solid var(--edge)', 'margin-top': 'auto'},
      ),
      css('.demo-count').styles(
        color: .variable('--zon'),
        fontSize: 17.px,
        fontWeight: .w600,
      ),
    ]),

    // Keyframes must sit at the top level — they cannot nest in a selector.
    css.keyframes('demo-in', {
      '0%': Styles(opacity: 0, transform: .translate(y: (-8).px)),
      '100%': Styles(opacity: 1, transform: .translate(y: .zero)),
    }),
    css.keyframes('demo-flash', {
      '0%': Styles(backgroundColor: .rgba(47, 224, 172, 0.22)),
      '100%': Styles(backgroundColor: .rgba(255, 255, 255, 0.02)),
    }),
  ];
}
