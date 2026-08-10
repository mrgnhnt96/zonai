/// The copyable install line under the hero CTAs.
library;

import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

@client
class InstallCommand extends StatefulComponent {
  const InstallCommand({required this.command, super.key});

  final String command;

  @override
  State<InstallCommand> createState() => InstallCommandState();
}

class InstallCommandState extends State<InstallCommand> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    if (!kIsWeb) return;

    web.window.navigator.clipboard.writeText(component.command);
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Component build(BuildContext context) {
    return button(
      classes: _copied ? 'install install-copied' : 'install',
      onClick: _copy,
      attributes: {'aria-label': 'Copy install command', 'title': 'Copy to clipboard'},
      [
        span(classes: 'install-prompt', [.text(r'$')]),
        span(classes: 'install-cmd', [.text(component.command)]),
        span(classes: 'install-copy', [.text(_copied ? 'copied' : 'copy')]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.install', [
      css('&').styles(
        display: .inlineFlex,
        maxWidth: 100.percent,
        padding: .symmetric(vertical: 10.px, horizontal: 14.px),
        border: .all(color: .variable('--edge'), width: 1.px),
        radius: .circular(10.px),
        cursor: .pointer,
        transition: Transition.combine([
          Transition('border-color', duration: 160.ms),
          Transition('background-color', duration: 160.ms),
        ]),
        alignItems: .center,
        gap: .all(10.px),
        fontFamily: .variable('--mono'),
        fontSize: 13.px,
        backgroundColor: .rgba(255, 255, 255, 0.025),
      ),
      css('&:hover').styles(
        backgroundColor: .rgba(255, 255, 255, 0.05),
        raw: {'border-color': 'var(--zon-deep)'},
      ),
      css('.install-prompt').styles(color: .variable('--zon-deep'), raw: {'flex': '0 0 auto'}),
      css('.install-cmd').styles(
        overflow: .hidden,
        color: .variable('--fg'),
        textOverflow: .ellipsis,
        whiteSpace: .noWrap,
        // Without this a flex item refuses to shrink below its content width,
        // and this one holds a very long URL — it would widen the whole hero.
        raw: {'min-width': '0'},
      ),
      css('.install-copy').styles(
        padding: .symmetric(vertical: 2.px, horizontal: 7.px),
        radius: .circular(5.px),
        color: .variable('--fg-mute'),
        fontSize: 10.px,
        textTransform: .upperCase,
        letterSpacing: 0.8.px,
        backgroundColor: .rgba(255, 255, 255, 0.05),
        raw: {'flex': '0 0 auto'},
      ),
      css('&.install-copied').styles(raw: {'border-color': 'var(--zon)'}),
      css('&.install-copied .install-copy').styles(
        color: .variable('--void'),
        backgroundColor: .variable('--zon'),
      ),
    ]),
  ];
}
