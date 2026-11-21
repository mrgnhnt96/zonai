import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/init_scaffold.dart';

/// `zonai init` used to scaffold only the admin table rules. With table rules
/// and no row rules, the admin sign-in (`POST /auth`) failed with a 500 and the
/// dashboard said "Sign in failed" on a brand-new project (backlog B783).
void main() {
  group('zonai init scaffolds the admin rules', () {
    late Map<String, String> files;

    setUp(() => files = initScaffoldDartFiles());

    test('writes the admin table rules', () {
      expect(
        files['lib/src/rules/admin_table_rules.dart'],
        contains('extends AuthTableRules<AdminTable, Admin>'),
      );
    });

    test('writes the admin row rules next to them', () {
      expect(
        files['lib/src/rules/admin_row_rules.dart'],
        allOf(
          contains("import '../schemas/admins.dart';"),
          contains('AdminRowRules main() => AdminRowRules();'),
          contains('extends AuthRowRules<AdminTable, Admin>'),
          contains('super(admins)'),
        ),
      );
    });

    test('the row rules target the scaffolded admins table', () {
      expect(
        files['lib/src/schemas/admins.dart'],
        allOf(
          contains('final class AdminTable extends AuthTable<Admin>'),
          contains("final admins = authTable('admins', AdminTable.new);"),
        ),
      );
    });
  });
}
