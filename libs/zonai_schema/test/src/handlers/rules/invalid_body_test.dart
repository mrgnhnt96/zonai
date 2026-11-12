import 'package:test/test.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A create or update whose body leaves a required column out, sends it as
/// null, or sends the wrong type used to throw a `TypeError` from inside the
/// app's `fromRow`, before its row rule ran, and the caller got a 500. It is
/// refused as an [InvalidBodyException] naming the column (a 400), and the
/// rule is never asked.

final class _Recording {
  const _Recording({required this.id, required this.apiKey});

  final int? id;
  final String apiKey;
}

final class _RecordingTable extends Table<_Recording> {
  _RecordingTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      apiKey = $.text('api_key', (s) => s.apiKey);

  final ColumnType<int?> id;
  final TextColumn apiKey;

  @override
  _Recording fromRow(RowReader read) =>
      _Recording(id: read(id), apiKey: read(apiKey));
}

final _recordings = sqliteTable('recordings', _RecordingTable.new);

/// Allows everything, and counts how often it was asked.
final class _CountingRowRules extends RowRules<_RecordingTable, _Recording> {
  _CountingRowRules() : super(_recordings);

  var asked = 0;

  @override
  Future<bool> canView(Jwt? jwt, _Recording row) async => ++asked > 0;

  @override
  Future<bool> canCreate(Jwt? jwt, _Recording row) async => ++asked > 0;

  @override
  Future<bool> canUpdate(Jwt? jwt, _Recording before, _Recording after) async =>
      ++asked > 0;

  @override
  Future<bool> canDelete(Jwt? jwt, _Recording row) async => ++asked > 0;
}

void main() {
  late _CountingRowRules rowRules;
  late DbRules rules;

  setUp(() {
    rowRules = _CountingRowRules();
    rules = DbRules(rules: [rowRules]);
  });

  Future<bool> create(Map<String, dynamic> object) async {
    final response = await rules.dispatch(
      RowRulesRequest(
        table: 'recordings',
        operation: 'create',
        data: object,
        jwt: null,
      ),
    );
    return (response! as RowRulesResponse).canPerform;
  }

  Matcher refusedWith(String message) => throwsA(
    isA<InvalidBodyException>().having((e) => e.message, 'message', message),
  );

  test(
    'a create missing a required column is refused before its rule',
    () async {
      await expectLater(
        create({'id': 1}),
        refusedWith('Column "api_key" on "recordings" is required'),
      );
      expect(rowRules.asked, 0);
    },
  );

  test('a create sending a required column as null is refused', () async {
    await expectLater(
      create({'id': 1, 'api_key': null}),
      refusedWith('Column "api_key" on "recordings" cannot be null'),
    );
    expect(rowRules.asked, 0);
  });

  test('a create sending the wrong type is refused', () async {
    await expectLater(
      create({'id': 1, 'api_key': 42}),
      refusedWith('Column "api_key" on "recordings" cannot hold a int'),
    );
    expect(rowRules.asked, 0);
  });

  test('a correct create still reaches its rule', () async {
    expect(await create({'id': 1, 'api_key': 'k'}), isTrue);
    expect(rowRules.asked, 1);
  });

  test('a batch create is refused the same way', () async {
    await expectLater(
      rules.dispatch(
        BatchRowRulesRequest(
          table: 'recordings',
          operation: 'create',
          rows: [
            {'id': 1, 'api_key': 'k'},
            {'id': 2},
          ],
          jwt: null,
        ),
      ),
      refusedWith('Column "api_key" on "recordings" is required'),
    );
  });

  test('an update setting a required column to null is refused', () async {
    await expectLater(
      rules.dispatch(
        RowRulesRequest(
          table: 'recordings',
          operation: 'update',
          data: const {'id': 1, 'api_key': 'k'},
          updates: [
            Update.object(const {'api_key': null}),
          ],
          jwt: null,
        ),
      ),
      refusedWith('Column "api_key" on "recordings" cannot be null'),
    );
    expect(rowRules.asked, 0);
  });
}
