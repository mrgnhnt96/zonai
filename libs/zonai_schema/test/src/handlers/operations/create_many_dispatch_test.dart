import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

// POST /db/many failed every time it ran against a real operations worker:
// "type 'Null' is not a subtype of type 'Map<String, dynamic>'".
//
// A create-many request carries `operation: create`, because its rules and
// policies are the create ones. The worker decodes a request by its operation,
// so it read a create-many as a single create and went looking for `object`,
// when the payload carries `objects`. In-process dispatch hands the typed
// request straight over and never decodes it, which is why nothing local
// caught it.

final class _Note {
  const _Note({required this.id, required this.title});

  final int? id;
  final String title;
}

final class _NoteTable extends Table<_Note> {
  _NoteTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      title = $.text('title', (s) => s.title);

  final ColumnType<int?> id;
  final TextColumn title;

  @override
  _Note fromRow(RowReader read) => _Note(id: read(id), title: read(title));
}

final _notes = table('create_many_notes', _NoteTable.new);

class _FakeMessageIo implements MessageIo {
  final _incoming = StreamController<Map<String, dynamic>>();
  final List<Map<String, dynamic>> sent = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  void dispose() => _incoming.close();

  void push(Map<String, dynamic> message) => _incoming.add(message);
}

Future<void> _waitUntil(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// What the worker does with a message: JSON over the wire, then
/// [Request.fromJson] and [OperationRequest.fromRequest].
OperationRequest _overTheWire(OperationRequest request) {
  final wire = jsonDecode(jsonEncode(request.toJson())) as Map<String, dynamic>;
  return OperationRequest.fromRequest(Request.fromJson(wire) as UnknownRequest);
}

void main() {
  group('decoding a perform request', () {
    test('a create-many comes back a create-many, with every object', () {
      final decoded = _overTheWire(
        CreateManyOperationRequest(
          table: 'create_many_notes',
          objects: [
            {'title': 'a'},
            {'title': 'b'},
          ],
          jwt: null,
        ),
      );

      expect(
        decoded,
        isA<CreateManyOperationRequest>()
            .having((r) => r.table, 'table', 'create_many_notes')
            .having((r) => r.operation, 'operation', 'create')
            .having((r) => r.objects, 'objects', [
              {'title': 'a'},
              {'title': 'b'},
            ]),
      );
    });

    test('a single create still comes back a single create', () {
      final decoded = _overTheWire(
        CreateOperationRequest(
          table: 'create_many_notes',
          object: {'title': 'a'},
          jwt: null,
        ),
      );

      expect(
        decoded,
        isA<CreateOperationRequest>().having((r) => r.object, 'object', {
          'title': 'a',
        }),
      );
    });

    // PATCH and DELETE /db/many send the same where-based request as their
    // single forms, so they have no second shape to confuse.
    test('an update and a delete come back as themselves', () {
      final update = _overTheWire(
        UpdateOperationRequest(
          table: 'create_many_notes',
          where: const Eq('title', 'a'),
          updates: [Update.column('title', const Literal('b'))],
          jwt: null,
        ),
      );
      final delete = _overTheWire(
        DeleteOperationRequest(
          table: 'create_many_notes',
          where: const Eq('title', 'a'),
          limit: null,
          jwt: null,
        ),
      );

      expect(update, isA<UpdateOperationRequest>());
      expect(delete, isA<DeleteOperationRequest>());
    });
  });

  test('the operations worker builds one insert for a create-many', () async {
    final io = _FakeMessageIo();
    DbOperations(operations: const [], tables: [_notes]).start(io: io);

    final request = CreateManyOperationRequest(
      table: 'create_many_notes',
      objects: [
        {'title': 'a'},
        {'title': 'b'},
      ],
      jwt: null,
    );
    io.push(jsonDecode(jsonEncode(request.toJson())) as Map<String, dynamic>);

    await _waitUntil(() => io.sent.isNotEmpty);
    io.dispose();

    final reply = io.sent.single;
    expect(reply['id'], request.id);
    expect(
      reply['path'],
      'response/.operation.perform',
      reason: 'the worker refused the request: ${reply['error']}',
    );
    expect(reply['query'], startsWith('INSERT INTO'));
    expect(reply['values'], containsAllInOrder(['a', 'b']));
  });
}
