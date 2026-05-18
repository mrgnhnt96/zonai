import 'package:jaspr/dom.dart';

const primaryColor = Color('#01589B');
const surfaceColor = Color('#ffffff');
const borderColor = Color('#e2e8f0');

@css
List<StyleRule> get styles => [
  css.import('https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap'),
  css('html, body').styles(
    width: 100.percent,
    minHeight: 100.vh,
    padding: .zero,
    margin: .zero,
    boxSizing: .borderBox,
    fontFamily: const .list([FontFamily('Inter'), FontFamilies.sansSerif]),
    backgroundColor: const Color('#f1f5f9'),
    color: const Color('#0f172a'),
  ),
  css('*', [css('&').styles(boxSizing: .inherit)]),
];
