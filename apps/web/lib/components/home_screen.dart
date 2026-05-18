import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../constants/theme.dart';
import '../providers/sqlite_tables_provider.dart';

class HomeScreen extends StatelessComponent {
  const HomeScreen({super.key});

  @override
  Component build(BuildContext context) {
    final tables = context.watch(sqliteTablesProvider);
    return main_(classes: 'home', [
      aside(classes: 'tables-pane', [
        div(classes: 'tables-pane-header', [.text('Tables')]),
        if (tables.loadError case final error?)
          div(classes: 'tables-pane-error', [
            p(classes: 'tables-pane-msg', [.text('Could not load tables.')]),
            p(classes: 'tables-pane-err-detail', [.text(error)]),
          ])
        else if (tables.names.isEmpty)
          p(classes: 'tables-pane-msg', [.text('No tables yet.')])
        else
          ul(classes: 'tables-list', [
            for (final name in tables.names) li(classes: 'tables-item', [.text(name)]),
          ]),
      ]),
      div(classes: 'home-main', [
        div(classes: 'card', [
          h1(classes: 'title', [.text('Welcome home')]),
          p(classes: 'subtitle', [.text('You are signed in.')]),
          button(classes: 'sign-out', type: .button, onClick: () => context.read(authProvider.notifier).signOut(), [
            .text('Sign out'),
          ]),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.home', [
      css('&').styles(
        flex: Flex(grow: 1, shrink: 0),
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .stretch,
        minHeight: 100.vh,
        width: 100.percent,
      ),
      css('.tables-pane').styles(
        width: 260.px,
        flex: Flex(grow: 0, shrink: 0),
        backgroundColor: surfaceColor,
        border: Border.only(
          right: BorderSide.solid(color: borderColor, width: 1.px),
        ),
        padding: .symmetric(horizontal: 16.px, vertical: 20.px),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(12.px),
      ),
      css('.tables-pane-header').styles(
        fontSize: 0.75.rem,
        fontWeight: .w600,
        letterSpacing: 0.04.rem,
        color: const Color('#64748b'),
        textTransform: .upperCase,
      ),
      css('.tables-pane-msg').styles(fontSize: 0.875.rem, color: const Color('#64748b')),
      css('.tables-pane-error').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(8.px)),
      css(
        '.tables-pane-err-detail',
      ).styles(fontSize: 0.75.rem, color: const Color('#b91c1c'), raw: {'overflow-wrap': 'anywhere'}),
      css('.tables-list').styles(
        margin: .zero,
        padding: .zero,
        listStyle: .none,
        overflow: Overflow.auto,
        flex: Flex(grow: 1, shrink: 1),
      ),
      css('.tables-item').styles(
        padding: .symmetric(vertical: 8.px, horizontal: 10.px),
        margin: .only(bottom: 4.px),
        radius: .all(Radius.circular(8.px)),
        fontSize: 0.875.rem,
        fontWeight: .w500,
      ),
      css('.tables-item:hover').styles(backgroundColor: const Color('#f8fafc')),
      css('.home-main').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        padding: .all(24.px),
      ),
      css('.card').styles(
        width: 100.percent,
        maxWidth: 480.px,
        backgroundColor: surfaceColor,
        padding: .all(32.px),
        radius: .all(Radius.circular(16.px)),
        shadow: BoxShadow(
          offsetX: Unit.zero,
          offsetY: 12.px,
          blur: 40.px,
          spread: (-8).px,
          color: Colors.black.withOpacity(0.08),
        ),
      ),
      css('.title').styles(
        margin: .only(bottom: 8.px),
        fontSize: 1.5.rem,
        fontWeight: .w600,
      ),
      css('.subtitle').styles(
        margin: .only(bottom: 24.px),
        fontSize: 0.95.rem,
        color: const Color('#64748b'),
      ),
      css('.sign-out').styles(
        margin: .only(top: 8.px),
        padding: .symmetric(horizontal: 16.px, vertical: 10.px),
        cursor: .pointer,
        radius: .all(Radius.circular(8.px)),
        border: .all(color: borderColor, width: 1.px, style: .solid),
        fontWeight: .w600,
        fontSize: 0.875.rem,
        color: primaryColor,
        backgroundColor: Colors.transparent,
      ),
      css('.sign-out:hover').styles(backgroundColor: const Color('#f8fafc')),
    ]),
  ];
}
