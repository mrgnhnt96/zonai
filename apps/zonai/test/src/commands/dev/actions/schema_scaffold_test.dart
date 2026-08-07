import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/schema_scaffold.dart';
import 'package:zonai/src/utils/schema_names.dart';

void main() {
  group('appendUnionIdCase', () {
    test('inserts a switch case with consistent indentation', () {
      final names = SchemaNames.fromEntityClass('Product', usedIdSuffixes: {'it'});
      const content = '''
    return switch (parts[1]) {
      ItemsId._suffix => ItemsId(json),
      _ => throw ArgumentError('Invalid ID format: \$json'),
    };
''';

      final updated = appendUnionIdCase(content, names);

      expect(
        updated,
        contains(
          '      ItemsId._suffix => ItemsId(json),\n'
          '      ProductsId._suffix => ProductsId(json),\n'
          '      _ => throw ArgumentError',
        ),
      );
      expect(updated, isNot(contains('            ProductsId')));
    });
  });

  group('scaffoldStandaloneIdClass', () {
    test('compares against the generic z.Id interface, not the concrete class', () {
      final names = SchemaNames.fromEntityClass('Recording', usedIdSuffixes: {});

      final source = scaffoldStandaloneIdClass(names);

      // A concrete-type check here would make equality direction-dependent
      // against other z.Id implementations (e.g. z.UnknownId from a JWT):
      // `unknownId == recordingsId` would pass while
      // `recordingsId == unknownId` failed, breaking ownership comparisons
      // written as `row.ownerId == jwt.userId`.
      expect(source, contains('other is z.Id && other.value == value'));
      expect(source, isNot(contains('other is ${names.idClass} &&')));
    });
  });

  group('scaffoldSchemaSource auth tables', () {
    final names = SchemaNames.fromEntityClass('User', usedIdSuffixes: {});

    test('scaffolds selected auth mixins without password fields', () {
      final source = scaffoldSchemaSource(
        names: names,
        kind: SchemaTableKind.auth,
        authConfig: const SchemaAuthConfig(
          password: false,
          otp: true,
          magicLink: true,
        ),
      );

      expect(source, contains('with OtpAuth, MagicLinkAuth'));
      expect(source, isNot(contains('PasswordAuth')));
      expect(source, isNot(contains('passwordHash')));
    });

    test('includes AsAdmin and canEdit override when requested', () {
      final source = scaffoldSchemaSource(
        names: names,
        kind: SchemaTableKind.auth,
        authConfig: const SchemaAuthConfig(
          password: true,
          isAdmin: true,
          canEdit: false,
        ),
      );

      expect(source, contains('with PasswordAuth, AsAdmin'));
      expect(source, contains('bool get canEdit => false'));
    });
  });
}
