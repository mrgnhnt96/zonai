import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/components/syntax_highlighted_code.dart';
import 'package:zonai_web/utils/table_where_format.dart';

void main() {
  group('highlightedSourceText', () {
    test('preserves JSON line breaks and indentation', () {
      final source = formatListBodyJson(table: 'items', where: And([const Eq('a', 1), const Null('b')]));
      expect(source, contains('\n'));

      final highlighted = highlightedSourceText(source, SyntaxHighlightLanguage.json);
      expect(highlighted, source);
    });

    test('preserves Dart line breaks and indentation', () {
      final source = formatListBodyDart(table: 'users', where: And([const Eq('a', 1), const Null('b')]));
      expect(source, contains('\n'));

      final highlighted = highlightedSourceText(source, SyntaxHighlightLanguage.dart);
      expect(highlighted, source);
    });
  });
}
