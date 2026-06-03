import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'ui_styles.dart';

class ZonaiPageTitle extends StatelessComponent {
  const ZonaiPageTitle(this.text, {super.key});

  final String text;

  @override
  Component build(BuildContext context) {
    return h1(classes: ZonaiClasses.pageTitle, [.text(text)]);
  }
}

class ZonaiPageSubtitle extends StatelessComponent {
  const ZonaiPageSubtitle(this.text, {super.key});

  final String text;

  @override
  Component build(BuildContext context) {
    return p(classes: ZonaiClasses.pageSubtitle, [.text(text)]);
  }
}

class ZonaiErrorText extends StatelessComponent {
  const ZonaiErrorText(this.text, {super.key});

  final String text;

  @override
  Component build(BuildContext context) {
    return p(classes: ZonaiClasses.errorText, [.text(text)]);
  }
}

class ZonaiSectionLabel extends StatelessComponent {
  const ZonaiSectionLabel(this.text, {super.key});

  final String text;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.sectionLabel, [.text(text)]);
  }
}
