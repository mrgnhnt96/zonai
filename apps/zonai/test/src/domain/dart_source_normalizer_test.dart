import 'package:test/test.dart';
import 'package:zonai/src/domain/dart_source_normalizer.dart';

void main() {
  group('normalizeDartSource', () {
    test('drops line comments', () {
      expect(
        normalizeDartSource('enum Op { get } // a trailing note'),
        normalizeDartSource('enum Op { get }'),
      );
    });

    test('drops doc comments', () {
      expect(
        normalizeDartSource('''
/// Explains the enum at length.
///
/// And keeps going.
enum Op { get }
'''),
        normalizeDartSource('enum Op { get }'),
      );
    });

    test('drops nested block comments', () {
      expect(
        normalizeDartSource('enum /* outer /* inner */ still */ Op { get }'),
        normalizeDartSource('enum Op { get }'),
      );
    });

    test('collapses whitespace and indentation', () {
      expect(
        normalizeDartSource('enum Op {\n\n      get,\n\tlist,\n}'),
        'enum Op { get, list, }',
      );
    });

    // The JSON keys handlers parse are string literals, so a rename has to be
    // visible or the hash misses exactly the change it exists to catch.
    test('keeps string literals verbatim', () {
      expect(
        normalizeDartSource("payload['customOperation']"),
        isNot(normalizeDartSource("payload['custom_operation']")),
      );
    });

    test('does not treat // inside a string as a comment', () {
      expect(
        normalizeDartSource(
          "const url = 'https://docs.zonai.dev/x'; var a = 1;",
        ),
        contains('var a = 1;'),
      );
      expect(
        normalizeDartSource("const url = 'https://a'; var a = 1;"),
        isNot(normalizeDartSource("const url = 'https://b'; var a = 1;")),
      );
    });

    test('does not treat /* inside a string as a comment', () {
      expect(
        normalizeDartSource("const a = '/*'; const b = 2;"),
        contains('const b = 2;'),
      );
    });

    test('handles escaped quotes', () {
      expect(
        normalizeDartSource(r"const a = 'it\'s'; const b = 2;"),
        contains('const b = 2;'),
      );
    });

    test('handles raw strings, where a backslash escapes nothing', () {
      expect(
        normalizeDartSource(r"final re = RegExp(r'\'); const b = 2;"),
        contains('const b = 2;'),
      );
    });

    test('handles triple-quoted strings spanning lines', () {
      expect(
        normalizeDartSource("""
const a = '''
line one // not a comment
line two
''';
const b = 2;
"""),
        contains('const b = 2;'),
      );
    });

    test('handles a quote inside an interpolated expression', () {
      expect(
        normalizeDartSource("""final a = '\${map['key']}'; const b = 2;"""),
        contains('const b = 2;'),
      );
    });

    // Hashing runs over whatever is on disk, including a file being typed in.
    test(
      'an unterminated literal ends at the newline instead of eating the file',
      () {
        expect(
          normalizeDartSource("const a = 'oops\nconst b = 2;"),
          contains('const b = 2;'),
        );
      },
    );
  });
}
