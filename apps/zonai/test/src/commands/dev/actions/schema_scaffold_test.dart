import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/schema_scaffold.dart';
import 'package:zonai/src/utils/schema_names.dart';

void main() {
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
