import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'ui_styles.dart';

/// Inline error panel for data-loading failures.
class ZonaiErrorAlert extends StatelessComponent {
  const ZonaiErrorAlert({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.alertError, [
      p(classes: ZonaiClasses.alertTitle, [.text(title)]),
      pre(classes: ZonaiClasses.alertBody, [.text(body)]),
    ]);
  }
}
