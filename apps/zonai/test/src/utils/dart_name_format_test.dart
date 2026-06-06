import 'package:test/test.dart';
import 'package:zonai/src/utils/dart_name_format.dart';

void main() {
  group('formatDartClassName', () {
    test('formats snake_case input', () {
      expect(formatDartClassName('user_operations'), 'UserOperations');
    });

    test('formats spaced words', () {
      expect(formatDartClassName('user operations'), 'UserOperations');
    });

    test('preserves PascalCase input', () {
      expect(formatDartClassName('UserOperations'), 'UserOperations');
    });
  });

  group('pascalToSnake', () {
    test('converts class names to file stems', () {
      expect(pascalToSnake('UserOperations'), 'user_operations');
      expect(
        pascalToSnake('CellEditFixtureTableRules'),
        'cell_edit_fixture_table_rules',
      );
    });
  });

  group('cronNameFromClassName', () {
    test('derives cron names from class names', () {
      expect(cronNameFromClassName('CleanupUsersCron'), 'cleanup_users');
      expect(cronNameFromClassName('DailyReport'), 'daily_report');
    });
  });
}
