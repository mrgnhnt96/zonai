import 'dart:convert';

import 'package:raindrop_cli/src/core/snapshot.dart';
import 'package:test/test.dart';
import 'package:zonai/src/domain/destructive_migration.dart';

Map<String, Object?> _column(String name, String type, {bool pk = false}) => {
  'name': name,
  'type': type,
  'primaryKey': pk,
  'isNullable': !pk,
};

SchemaSnapshot _snapshot(Map<String, List<Map<String, Object?>>> tables) {
  return SchemaSnapshot.fromJson(
    jsonEncode({
      'version': '1',
      'dialect': 'sqlite',
      'id': 'x',
      'prevId': 'y',
      'indexes': <String, Object?>{},
      'foreignKeys': <String, Object?>{},
      'tables': {
        for (final MapEntry(key: name, value: columns) in tables.entries)
          name: {
            'name': name,
            'columns': {for (final c in columns) c['name']! as String: c},
          },
      },
    }),
  );
}

void main() {
  final id = _column('id', 'TEXT', pk: true);
  final title = _column('title', 'TEXT');
  final count = _column('count', 'INTEGER');

  group('destructiveChanges', () {
    test('nothing, for an additive change', () {
      final from = _snapshot({
        'notes': [id, title],
      });
      final to = _snapshot({
        'notes': [id, title, count],
        'tags': [id],
      });

      expect(destructiveChanges(from, to), isEmpty);
    });

    test('nothing, for the first migration', () {
      expect(
        destructiveChanges(
          null,
          _snapshot({
            'notes': [id],
          }),
        ),
        isEmpty,
      );
    });

    test('a table that left the schema', () {
      final from = _snapshot({
        'notes': [id],
        'old_notes': [id],
      });
      final to = _snapshot({
        'notes': [id],
      });

      expect(destructiveChanges(from, to), [
        'drops table "old_notes" and every row in it',
      ]);
    });

    test('a column that left a table', () {
      final from = _snapshot({
        'notes': [id, title, count],
      });
      final to = _snapshot({
        'notes': [id, title],
      });

      expect(destructiveChanges(from, to), [
        'drops column "notes"."count" and its data',
      ]);
    });

    test('not a column raindrop recognises as renamed', () {
      // Same definition, new name: raindrop emits a rename, which keeps data.
      final from = _snapshot({
        'notes': [id, title],
      });
      final to = _snapshot({
        'notes': [id, _column('heading', 'TEXT')],
      });

      expect(destructiveChanges(from, to), isEmpty);
    });

    test('a renamed table: the old one is dropped', () {
      final from = _snapshot({
        'notes': [id, title],
      });
      final to = _snapshot({
        'memos': [id, title],
      });

      expect(destructiveChanges(from, to), [
        'drops table "notes" and every row in it',
      ]);
    });
  });
}
