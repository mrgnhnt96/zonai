import 'package:test/test.dart';
import 'package:zonai_schema/src/column_types/enum_list_column.dart';

enum _Tag { alpha, beta, gamma }

void main() {
  late EnumListTransformer<_Tag> transformer;

  setUp(() {
    transformer = EnumListTransformer<_Tag>(values: _Tag.values);
  });

  group('EnumListTransformer.encode', () {
    test('joins enum names for a multi-value list', () {
      expect(
        transformer.encode([_Tag.alpha, _Tag.beta]),
        'alpha,beta',
      );
    });

    test('encodes an empty list', () {
      expect(transformer.encode([]), '');
    });

    test('encodes values produced by decode from wire lists', () {
      expect(
        transformer.encode(transformer.decode(['alpha', 'beta'])),
        'alpha,beta',
      );
      expect(
        transformer.encode(transformer.decode([['alpha', 'beta']])),
        'alpha,beta',
      );
    });
  });

  group('EnumListTransformer.decode', () {
    test('decodes comma-separated wire text', () {
      expect(
        transformer.decode('alpha,beta'),
        [_Tag.alpha, _Tag.beta],
      );
    });

    test('decodes JSON-style string lists', () {
      expect(
        transformer.decode(['alpha', 'gamma']),
        [_Tag.alpha, _Tag.gamma],
      );
    });

    test('decodes empty string as empty list', () {
      expect(transformer.decode(''), isEmpty);
    });

    test('decodes JSON array wire text', () {
      expect(
        transformer.decode('["alpha","gamma"]'),
        [_Tag.alpha, _Tag.gamma],
      );
    });

    test('decodes a single nested list', () {
      expect(
        transformer.decode([['alpha', 'beta']]),
        [_Tag.alpha, _Tag.beta],
      );
    });
  });
}
