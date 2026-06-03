import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'ui_styles.dart';

/// Elevated surface for auth forms and focused content.
class ZonaiCard extends StatelessComponent {
  const ZonaiCard({super.key, required this.children});

  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.card, children);
  }
}
