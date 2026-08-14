// HTTP assertions for the e2e fixture layer (docs/testing-strategy.md Step 3).
//
// Invoked by tool/ci/run_e2e.sh against an already-running server that a REAL
// compiled binary is serving. It asserts on response bodies and on the rows
// that come back from an independent read -- never on exit codes, because
// every bug this layer exists for was invisible to "the command exited 0".
//
// Imports nothing outside the SDK on purpose: `dart run tool/ci/e2e/drive.dart`
// then works from a bare checkout on every runner with no `pub get` of its
// own, which is one less thing that can silently skip the whole layer.
//
// Usage:
//   dart run tool/ci/e2e/drive.dart --fixture <name> --base-url <url> \
//       --mode <label> --phase <seed|verify>
//
//   --phase seed    run the fixture's whole suite (this is the one that writes)
//   --phase verify  re-assert the expected FINAL state only, against a server
//                   that has been restarted since `seed` ran. A fresh process
//                   with a freshly opened database file is the cheapest read
//                   this harness has that shares nothing with the writes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final fixture = args['fixture'];
  final baseUrl = args['base-url'];
  final mode = args['mode'] ?? 'default';
  final phase = args['phase'] ?? 'seed';

  if (fixture == null || baseUrl == null) {
    stderr.writeln(
      'usage: drive.dart --fixture <name> --base-url <url> '
      '[--mode <label>] [--phase seed|verify]',
    );
    exit(64);
  }

  final api = Api(baseUrl: baseUrl, fixture: fixture, mode: mode);
  final suite = _suites[fixture];
  if (suite == null) {
    api.fail(
      'a suite exists for this fixture',
      expected: 'one of ${_suites.keys.join(', ')}',
      actual: fixture,
      why:
          'run_e2e.sh drove a fixture with no assertions. A fixture that only '
          'gets its lifecycle run is coverage of the lifecycle, not of the '
          'fixture -- so it fails here rather than passing quietly.',
    );
  }

  try {
    await suite(api, phase);
  } finally {
    api.close();
  }

  final known = api.knownFailures == 0
      ? ''
      : ', ${api.knownFailures} KNOWN FAILURE(S) reported above';
  stdout.writeln(
    'e2e ok: $fixture [$mode/$phase] -- ${api.passed} assertion(s)$known',
  );
}

// ---------------------------------------------------------------------------
// The suites
// ---------------------------------------------------------------------------

typedef Suite = Future<void> Function(Api api, String phase);

const _suites = <String, Suite>{
  'crud_matrix': _crudMatrix,
  'admin_password_update_repro': _adminPasswordUpdate,
  'signup_backfill_repro': _signupBackfill,
  'concurrency_repro': _concurrency,
};

/// The operator x column-type matrix, plus every mutation shape, plus the one
/// assertion in this repo that reaches the worker-side serializer.
///
/// Seeded rows -- `'007'` and `'7'` are distinct TEXT codes deliberately
/// (issue #21 was a leading-zero `Eq` that a SQL-builder unit test passed and
/// was closed wrongly once on the strength of it):
///
///   id     code   status   quantity  weight  active  note
///   w007   007    open     7         0.5     true    null
///   w7     7      open     7         1.5     true    "plain seven"
///   w0071  0071   open     71        2.5     false   null
///   w100   100    closed   100       3.5     true    "hundred"
Future<void> _crudMatrix(Api api, String phase) async {
  const seeds = [
    {
      'id': 'w007',
      'code': '007',
      'status': 'open',
      'quantity': 7,
      'weight': 0.5,
      'active': true,
      'note': null,
    },
    {
      'id': 'w7',
      'code': '7',
      'status': 'open',
      'quantity': 7,
      'weight': 1.5,
      'active': true,
      'note': 'plain seven',
    },
    {
      'id': 'w0071',
      'code': '0071',
      'status': 'open',
      'quantity': 71,
      'weight': 2.5,
      'active': false,
      'note': null,
    },
    {
      'id': 'w100',
      'code': '100',
      'status': 'closed',
      'quantity': 100,
      'weight': 3.5,
      'active': true,
      'note': 'hundred',
    },
  ];

  if (phase == 'verify') {
    // Everything below ran against a server that has since been stopped. This
    // is a different process with a freshly opened database file, so it shares
    // no cache, no connection and no in-memory state with the writes.
    final rows = await api.list('widgets', orderByColumn: 'code');
    api.expect(
      'the only row left after the deletes survives a server restart',
      actual: rows.map((r) => r['code']).toList(),
      expected: ['100'],
      why:
          'a16b499 shipped a mutation whose RESPONSE was wrong while the write '
          'landed. The inverse -- a response that looks right over a write that '
          'did not land -- is what this re-read after a restart catches.',
    );
    api.expect(
      'the surviving row still carries the values the ObjectUpdate set',
      actual: [rows.single['quantity'], rows.single['note']],
      expected: [101, 'objected'],
    );
    return;
  }

  // -- seed ---------------------------------------------------------------
  for (final seed in seeds) {
    final created = await api.create('widgets', seed);
    api.expect(
      'POST /db echoes back the row it created (${seed['id']})',
      actual: created['code'],
      expected: seed['code'],
    );
    final refetched = await api.get('widgets', _eq('id', seed['id']!));
    api.expect(
      'the created row is there when read back independently by id '
      '(${seed['id']})',
      actual: [refetched['code'], refetched['quantity'], refetched['note']],
      expected: [seed['code'], seed['quantity'], seed['note']],
    );
  }
  api.expect(
    'the seeded rows are the only rows',
    actual: await api.count('widgets'),
    expected: seeds.length,
  );

  // -- the worker-side serializer -----------------------------------------
  //
  // `gates`' row rule calls `get.many(... In('code', ['007','7']))` INSIDE the
  // rules worker, which is the one path a CLI release cannot reach: the worker
  // compiles its own copy of zonai_schema and serializes the clause with it
  // (02cfcef needed a second published release for exactly this). Visible
  // means the worker could serialize an `In` AND got the right two rows back.
  await api.create('gates', {'id': 'g1', 'label': 'worker-side In'});
  final gate = await api.get('gates', _eq('id', 'g1'));
  api.expect(
    "a rule's own get.many(In(...)) resolves inside the worker",
    actual: gate['label'],
    expected: 'worker-side In',
    why:
        '02cfcef: a rule calling get.* with an In/NotIn builds GetRecordRequest '
        'in the WORKER and serializes it with the published zonai_schema. '
        '551081f fixed the host copy only. The negative control for this rule '
        'runs after the deletes below.',
  );

  // -- reads: every operator, every column type ---------------------------
  await _expectCodes(
    api,
    "Eq on a TEXT column does not coerce '007' to a number",
    where: _eq('code', '007'),
    expected: ['007'],
    why:
        'issue #21. A numeric coercion matches "7" as well as (or instead of) '
        '"007". A count-only assertion can pass while the wrong row comes '
        'back, so this asserts the value.',
  );
  await _expectCodes(
    api,
    "Eq on a TEXT column still finds the unpadded '7'",
    where: _eq('code', '7'),
    expected: ['7'],
  );
  api.expect(
    "count agrees with list for the leading-zero Eq",
    actual: await api.count('widgets', where: _eq('code', '007')),
    expected: 1,
  );

  await _expectCodes(
    api,
    'In carries a list of values across the transport',
    where: _inOp('in', 'code', ['007', '0071']),
    expected: ['007', '0071'],
    why:
        '551081f: serializeWhereValues ended in .cast<Object>(), and a CastList '
        'cannot cross an isolate boundary. In/NotIn were broken on every '
        'released binary, and after a16b499 every PATCH built an In too.',
  );
  await _expectCodes(
    api,
    'NotIn carries a list of values across the transport',
    where: _inOp('not_in', 'code', ['007', '7', '0071']),
    expected: ['100'],
  );
  await _expectCodes(
    api,
    'In works on an INTEGER column too, not just TEXT',
    where: _inOp('in', 'quantity', [7, 71]),
    expected: ['007', '0071', '7'],
  );

  await _expectCodes(
    api,
    'Gt on an INTEGER column',
    where: _cmp('gt', 'quantity', 7),
    expected: ['0071', '100'],
  );
  await _expectCodes(
    api,
    'Gte on an INTEGER column',
    where: _cmp('gte', 'quantity', 71),
    expected: ['0071', '100'],
  );
  await _expectCodes(
    api,
    'Lt on an INTEGER column',
    where: _cmp('lt', 'quantity', 71),
    expected: ['007', '7'],
  );
  await _expectCodes(
    api,
    'Lte on a REAL column',
    where: _cmp('lte', 'weight', 1.5),
    expected: ['007', '7'],
  );
  await _expectCodes(
    api,
    'Eq on a BOOLEAN column (stored as 0/1)',
    where: _eq('active', false),
    expected: ['0071'],
  );
  await _expectCodes(
    api,
    'is_null on a nullable TEXT column',
    where: {'type': 'is_null', 'column': 'note'},
    expected: ['007', '0071'],
  );
  await _expectCodes(
    api,
    'not_null on a nullable TEXT column',
    where: {'type': 'not_null', 'column': 'note'},
    expected: ['100', '7'],
  );
  await _expectCodes(
    api,
    "starts_with keeps the leading zero significant",
    where: _cmp('starts_with', 'code', '00'),
    expected: ['007', '0071'],
  );
  await _expectCodes(
    api,
    'ends_with on a TEXT column',
    where: _cmp('ends_with', 'code', '71'),
    expected: ['0071'],
  );
  await _expectCodes(
    api,
    'contains on a TEXT column',
    where: _cmp('contains', 'code', '07'),
    expected: ['007', '0071'],
  );
  await _expectCodes(
    api,
    'and/or compose',
    where: {
      'type': 'and',
      'conditions': [
        _cmp('gte', 'quantity', 7),
        {
          'type': 'or',
          'conditions': [_eq('code', '007'), _eq('code', '100')],
        },
      ],
    },
    expected: ['007', '100'],
  );

  // -- mutations: response, then the row by id, then what must not move ----
  await api.mutation(
    name: "PATCH whose where matches on the column it is writing (one row)",
    why:
        'a16b499: _update refetched by REPLAYING payload.where, and an update '
        'that writes the column the where matched on moves the row out of its '
        'own clause. The write committed and the RESPONSE was wrong -- 500 on '
        'a compiled binary, a length assert under `dart test`.',
    mutate: () => api.patchOne(
      'widgets',
      where: _eq('status', 'closed'),
      updates: [_columnUpdate('status', 'settled')],
    ),
    response: (res) => api.expect(
      'the PATCH response carries the row as it is AFTER the write',
      actual: [res['code'], res['status']],
      expected: ['100', 'settled'],
    ),
    refetchById: () async {
      final row = await api.get('widgets', _eq('id', 'w100'));
      api.expect(
        'the row read back independently by id has the new status',
        actual: row['status'],
        expected: 'settled',
      );
    },
    untouched: () async {
      final rows = await api.list(
        'widgets',
        where: _inOp('not_in', 'id', ['w100']),
        orderByColumn: 'code',
      );
      api.expect(
        'no other row changed status',
        actual: rows.map((r) => '${r['code']}=${r['status']}').toList(),
        expected: ['007=open', '0071=open', '7=open'],
      );
    },
  );

  await api.mutation(
    name: 'PATCH /db/many whose where matches on the column it is writing',
    why:
        'the multi-row form of a16b499. Three rows leave the clause at once, so '
        'a read-back that replays the where returns an empty set and the '
        'before/after pair the extension hook gets has mismatched lengths.',
    mutate: () => api.patchMany(
      'widgets',
      where: _eq('status', 'open'),
      updates: [_columnUpdate('status', 'archived')],
    ),
    response: (res) {
      final rows = (res['rows'] as List).cast<Map<String, Object?>>();
      final seen = rows.map((r) => '${r['code']}=${r['status']}').toList()
        ..sort();
      api.expect(
        'the response lists every row it updated, with the new value',
        actual: seen,
        expected: ['0071=archived', '007=archived', '7=archived'],
      );
    },
    refetchById: () async {
      for (final id in ['w007', 'w7', 'w0071']) {
        final row = await api.get('widgets', _eq('id', id));
        api.expect(
          'row $id read back by id is archived',
          actual: row['status'],
          expected: 'archived',
        );
      }
    },
    untouched: () async {
      final row = await api.get('widgets', _eq('id', 'w100'));
      api.expect(
        'the row that was already out of the clause is untouched',
        actual: row['status'],
        expected: 'settled',
        why:
            'this is the assertion that catches a where matching too much. It '
            'has no analogue in a GET.',
      );
    },
  );

  await api.mutation(
    name: 'PATCH with an ObjectUpdate carrying several columns at once',
    why:
        'the shape the admin UI sends. A fix that special-cases one column in '
        'the map has dropped the others before (see '
        'admin_password_update_repro).',
    mutate: () => api.patchOne(
      'widgets',
      where: _eq('id', 'w100'),
      updates: [
        {
          'type': 'object',
          'object': {'note': 'objected', 'quantity': 101},
        },
      ],
    ),
    response: (res) => api.expect(
      'the response reflects every column in the object',
      actual: [res['note'], res['quantity'], res['status']],
      expected: ['objected', 101, 'settled'],
    ),
    refetchById: () async {
      final row = await api.get('widgets', _eq('id', 'w100'));
      api.expect(
        'both columns landed, read back by id',
        actual: [row['note'], row['quantity']],
        expected: ['objected', 101],
      );
    },
    untouched: () async {
      api.expect(
        'no row was created or removed by an update',
        actual: await api.count('widgets'),
        expected: seeds.length,
      );
    },
  );

  await api.mutation(
    name: 'PATCH matching zero rows is a 404, not a 500',
    why:
        'a16b499 also fixed this: "nothing matched" is an ordinary outcome of a '
        'conditional update, and a 500 left a caller unable to tell "the row is '
        'gone" from "zonai broke".',
    mutate: () => api.patchOneExpectingStatus(
      'widgets',
      where: _eq('code', 'no-such-code'),
      updates: [_columnUpdate('status', 'never')],
      expectedStatus: 404,
    ),
    response: (res) =>
        api.expect('the status is 404', actual: res['status'], expected: 404),
    refetchById: () async {
      final row = await api.get('widgets', _eq('id', 'w100'));
      api.expect(
        'the no-op update left the row it did not match alone',
        actual: row['status'],
        expected: 'settled',
      );
    },
    untouched: () async {
      api.expect(
        'the row count is unchanged by an update that matched nothing',
        actual: await api.count('widgets'),
        expected: seeds.length,
      );
    },
  );

  // -- deletes: the failure mode a GET does not have ----------------------
  await api.mutation(
    name: 'DELETE /db removes exactly the row its where names',
    why:
        "a where clause matching too much is DELETE's failure mode and not "
        "GET's: an over-broad GET returns extra rows a caller can notice, an "
        'over-broad DELETE destroys them.',
    mutate: () => api.deleteOne('widgets', where: _eq('code', '007')),
    response: (res) =>
        api.expect('DELETE answers 2xx', actual: res['status'], expected: 200),
    refetchById: () async {
      final res = await api.getExpectingStatus(
        'widgets',
        _eq('id', 'w007'),
        expectedStatus: 404,
      );
      api.expect(
        'the deleted row is gone when read by id',
        actual: res['status'],
        expected: 404,
      );
    },
    untouched: () async {
      final rows = await api.list('widgets', orderByColumn: 'code');
      api.expect(
        "the leading-zero delete did not take '7' with it",
        actual: rows.map((r) => r['code']).toList(),
        expected: ['0071', '100', '7'],
        why:
            'issue #21 again, on the delete path: coercing "007" to a number '
            'here deletes the wrong row and there is no response body to '
            'notice it in.',
      );
    },
  );

  await api.mutation(
    name: 'DELETE /db/many removes exactly the rows an In names',
    why:
        'combines the two: a list-valued clause (551081f) on the path where '
        'over-matching is destructive.',
    mutate: () =>
        api.deleteMany('widgets', where: _inOp('in', 'code', ['7', '0071'])),
    response: (res) => api.expect(
      'DELETE /db/many answers 2xx',
      actual: res['status'],
      expected: 200,
    ),
    refetchById: () async {
      api.expect(
        'one row is left',
        actual: await api.count('widgets'),
        expected: 1,
      );
    },
    untouched: () async {
      final rows = await api.list('widgets');
      api.expect(
        'the row left is the one no clause named',
        actual: rows.single['code'],
        expected: '100',
      );
    },
  );

  // -- the negative control for the worker-side rule ----------------------
  //
  // Without this, a rule that had silently degraded to `true` would be
  // indistinguishable from one that ran and passed.
  final denied = await api.getExpectingStatus(
    'gates',
    _eq('id', 'g1'),
    expectedStatus: 403,
  );
  api.expect(
    "the gate row is hidden once the codes its rule reads are gone",
    actual: denied['status'],
    expected: 403,
    why:
        'the positive control above proves the worker could serialize an In. '
        'This one proves the rule was consulted at all -- a rule stubbed to '
        'true passes the first and fails here.',
  );

  await _customOperations(api);
  await _streaming(api);
}

/// `PATCH /db/custom/:operation` and `.../many` -- a route with zero e2e
/// coverage until this fixture's WidgetOperations.custom() (issue #25's
/// design: string-keyed custom operations, an Update-typed result) started
/// implementing `restock`. Deletes its own scratch rows at the end so the
/// restart-durability check in `_crudMatrix`'s `verify` phase still sees
/// only `['100']`.
Future<void> _customOperations(Api api) async {
  await api.create('widgets', {
    'id': 'wop1',
    'code': 'op1',
    'status': 'closed',
    'quantity': 3,
    'weight': 1.0,
    'active': true,
  });
  final restocked = await api.custom(
    'widgets',
    operation: 'restock',
    where: _eq('id', 'wop1'),
  );
  api.expect(
    "PATCH /db/custom/restock runs the SERVER's logic, not the client's",
    actual: [restocked['quantity'], restocked['status']],
    expected: [13, 'open'],
    why:
        'the request carried no `updates` for quantity or status. A custom '
        'operation that just replayed `updates` (a plain PATCH by another '
        'name) would have left both alone -- the whole point of a named '
        'operation is that the server decides the effect, not the caller.',
  );

  await api.create('widgets', {
    'id': 'wop2',
    'code': 'op2',
    'status': 'closed',
    'quantity': 5,
    'weight': 1.0,
    'active': true,
  });
  final restockedMany = await api.customMany(
    'widgets',
    operation: 'restock',
    where: _inOp('in', 'id', ['wop1', 'wop2']),
  );
  final restockedRows = (restockedMany['rows'] as List)
      .cast<Map<String, Object?>>();
  api.expect(
    'PATCH /db/custom/restock/many applies to every row the where matches',
    actual: {for (final row in restockedRows) row['id']: row['quantity']},
    expected: {'wop1': 23, 'wop2': 15},
    why:
        'wop1 already carries the +10 from the single-row call above, so this '
        'also proves the operation composes rather than resetting state.',
  );

  final unknownOp = await api.customExpectingStatus(
    'widgets',
    operation: 'not-a-real-operation',
    where: _eq('id', 'wop1'),
    expectedStatus: 403,
  );
  api.expect(
    'an operation name absent from customOperations is denied, not silently run',
    actual: unknownOp['status'],
    expected: 403,
    why:
        "the base TableOperations.custom() throws UnimplementedError for any "
        'name it does not recognise, but the table-rule customOperations map '
        'is consulted first -- an unregistered name never reaches that code '
        'at all, and a 403 (not a 500) is what a caller sees.',
  );

  await api.deleteOne('widgets', where: _eq('id', 'wop1'));
  await api.deleteOne('widgets', where: _eq('id', 'wop2'));
}

/// `GET /db/stream`, `/stream/list`, `/stream/count` -- open the connection,
/// mutate through a SEPARATE connection, and look for the event.
///
/// This does not currently find one. A raw TCP probe against a live
/// crud_matrix server (2026-08-14, captured under
/// .showrunner/scratch/orchestrator-0814-e2e-full-surface/) received the 200
/// response headers for `GET /db/stream` and then zero body bytes for 35s
/// across three mutations to the exact row being watched -- not even the
/// initial snapshot `_streamOne` reads (apps/zonai/lib/src/db_mutator/
/// zonai_db/parts/stream_one.dart) before entering its `await for` loop. The
/// server log shows `Streaming query: ...` (the subscription was set up) but
/// never `Stream completed` and never an error -- `_stream()`'s underlying
/// `_resqlite.streamQuery()` subscription (__utils.dart) appears to either
/// never emit or emit into a buffer this app never flushes to the socket.
/// `/stream/list` additionally throws an UNCAUGHT
/// `type 'Null' is not a subtype of type 'Map<String, dynamic>' in type
/// cast` server-side while processing (visible only in the server log, not
/// over HTTP -- the connection just hangs the same way) -- a second, distinct
/// defect on the same route.
///
/// `zonai_client`'s generated db_data_source_impl.dart assumes exactly one
/// JSON value per received chunk with no cross-chunk buffering (see
/// [Api.openStream]'s doc comment) -- if the server never flushes a chunk,
/// every real consumer of these three routes is silently starved, not
/// merely leaking. This is reported via [Api.knownFailure] (gates nothing,
/// prints on every run) rather than fixed here: this leaf is about coverage,
/// and a fix landing without anyone having decided the intended flush/buffer
/// behavior would be a bigger, unreviewed change than "add the missing
/// test". See docs/testing-strategy.md's note on knownFailure().
Future<void> _streaming(Api api) async {
  await api.create('widgets', {
    'id': 'wstream1',
    'code': 'strm',
    'status': 'open',
    'quantity': 1,
    'weight': 1.0,
    'active': true,
  });

  await _assertStreamNeverDelivers(api, '/db/stream', {
    'table': 'widgets',
    'where': _eq('id', 'wstream1'),
    'expand': <String>[],
  });
  await _assertStreamNeverDelivers(api, '/db/stream/list', {
    'table': 'widgets',
    'expand': <String>[],
  });
  await _assertStreamNeverDelivers(api, '/db/stream/count', {
    'table': 'widgets',
    'where': _eq('id', 'wstream1'),
  });

  await api.deleteOne('widgets', where: _eq('id', 'wstream1'));
}

Future<void> _assertStreamNeverDelivers(
  Api api,
  String path,
  Map<String, Object?> body,
) async {
  final session = await api.openStream(path, body: body);

  // The event this exists to catch: open, mutate elsewhere, expect the
  // change to arrive. Mutating BEFORE checking for the initial snapshot so a
  // fix that only delivers the initial value (and still never pushes
  // updates) does not read as "now passes".
  await api.patchOne(
    'widgets',
    where: _eq('id', 'wstream1'),
    updates: [_columnUpdate('quantity', 2)],
  );

  final event = await api.nextStreamEvent(session);
  api.knownFailure(
    'GET $path delivers an event over HTTP',
    actual: identical(event, Api.noStreamEvent)
        ? 'no event within 8s (0 bytes past the response headers)'
        : 'an event arrived: ${jsonEncode(event)}',
    expected: 'an event arrived',
    found:
        '2026-08-14, e2e-full-surface leaf (see this function\'s doc comment '
        'for the full raw-socket reproduction)',
    why:
        "a stream test that only checks the first event is the one that "
        'misses a leak -- this one does not even get that far, so the leak '
        'question is moot until delivery works at all.',
  );

  // Close from the client side regardless of whether an event arrived --
  // this is the trigger for the server's onCancel path (HybridStreamEngine /
  // revali asBroadcastStream: two prior leaks in this repo both lived
  // there). What this driver CAN assert afterward is that the server keeps
  // answering unrelated requests normally; it CANNOT assert that the
  // server-side subscription was actually torn down -- that needs a
  // process-level probe (handle/memory count), which is what the leak-scan
  // harness under stress/ is for, not an HTTP-only driver like this one.
  await session.close();
  final afterClose = await api.get('widgets', _eq('id', 'wstream1'));
  api.expect(
    'the server keeps answering ordinary requests after a stream client '
    'disconnects, and the mutation the stream never saw is really there',
    actual: afterClose['quantity'],
    expected: 2,
    why:
        'the weakest thing this HTTP-only driver can assert about "did '
        'closing the stream wedge the server" -- an actual leak/handle-'
        'exhaustion check needs a process-level probe this driver does not '
        'have (see the leak-scan harness under stress/).',
  );
}

/// Sign-in over HTTP after a password edit, through a compiled binary.
///
/// The in-repo test for this fixture drives `ZonaiDb` in-process. The bug it
/// was written for (`_hashPasswordUpdates` dropping an `ObjectUpdate` on the
/// floor) is in the mutation path either way, but only this route proves the
/// HTTP surface -- /auth/sign-in, and the 401 the old password must now get.
Future<void> _adminPasswordUpdate(Api api, String phase) async {
  const email = 'admin@example.com';
  const oldPassword = 'old-admin-password-1';
  const newPassword = 'new-admin-password-2';

  if (phase == 'verify') {
    final signIn = await api.signIn(
      table: 'admins',
      email: email,
      password: newPassword,
    );
    api.expect(
      'the new password still works after a server restart',
      actual: signIn['accessToken'] != null,
      expected: true,
      why:
          'proves the password hash was written to the database file, not just '
          'reflected in a response.',
    );
    return;
  }

  final signUp = await api.signUp(
    table: 'admins',
    email: email,
    password: oldPassword,
  );
  final adminId = signUp['user'] is Map
      ? (signUp['user'] as Map)['id']
      : signUp['id'];
  final token = signUp['accessToken'] as String?;
  api.expect(
    'sign-up returns an access token and an id',
    actual: [token != null, adminId != null],
    expected: [true, true],
  );
  api.expect(
    'sign-up does not verify the account by default',
    actual: _truthy(
      (signUp['user'] is Map ? (signUp['user'] as Map) : signUp)['is_verified'],
    ),
    expected: false,
  );

  // A second row that no PATCH below names, so "what must not change" has a
  // subject. Created through /auth/sign-up rather than POST /db so its
  // password goes through the same hashing path.
  const bystanderEmail = 'bystander@example.com';
  const bystanderPassword = 'bystander-password-1';
  await api.signUp(
    table: 'admins',
    email: bystanderEmail,
    password: bystanderPassword,
  );

  await api.mutation(
    name: 'PATCH /db sets a new password via an ObjectUpdate, and it works',
    why:
        "_hashPasswordUpdates hashed the new password in place on the map but "
        "its ObjectUpdate branch `continue`d without adding the update back to "
        'the result list, so the whole update never reached SQL -- and the '
        'response looked fine.',
    mutate: () => api.patchOne(
      'admins',
      where: _eq('id', adminId!),
      updates: [
        {
          'type': 'object',
          'object': {'password': newPassword, 'is_verified': true},
        },
      ],
      authorization: token,
    ),
    response: (res) => api.expect(
      'the response carries the non-password column from the same '
      'ObjectUpdate',
      actual: _truthy(res['is_verified']),
      expected: true,
      why:
          'a fix that special-cases the password column has dropped its '
          'neighbours in the same map before. The password itself is never in '
          'a response, which is why the two assertions below exist.',
    ),
    refetchById: () async {
      final row = await api.get(
        'admins',
        _eq('id', adminId!),
        authorization: token,
      );
      api.expect(
        'is_verified landed, read back independently by id',
        actual: _truthy(row['is_verified']),
        expected: true,
      );
      final signIn = await api.signIn(
        table: 'admins',
        email: email,
        password: newPassword,
      );
      api.expect(
        'the new password signs in',
        actual: signIn['accessToken'] != null,
        expected: true,
      );
      final rejected = await api.signInExpectingFailure(
        table: 'admins',
        email: email,
        password: oldPassword,
      );
      api.expect(
        'the old password no longer signs in',
        actual: rejected >= 400,
        expected: true,
        why:
            'without this, a path that stored the new password WITHOUT hashing '
            'it -- or never wrote it at all while leaving the old hash in '
            'place -- passes the assertion above.',
      );
    },
    untouched: () async {
      final signIn = await api.signIn(
        table: 'admins',
        email: bystanderEmail,
        password: bystanderPassword,
      );
      api.expect(
        "the other admin's password was not rewritten",
        actual: signIn['accessToken'] != null,
        expected: true,
        why:
            'an UPDATE whose where matched too much would have re-hashed every '
            'row, and every other assertion here would still pass.',
      );
    },
  );

  await _authSurface(api);
  await _operationalSurface(api);
  await _photoSurface(api);
}

/// Auth routes beyond sign-in/sign-up: refresh, reset-password, verify-email,
/// confirm, admin sign-in, logout, logout-all, and the generic multiplexed
/// `POST /auth`. Each gets its own scratch admin so none of these interfere
/// with each other or with `_adminPasswordUpdate`'s own fixture state.
///
/// NOT covered, and why: `POST /auth/confirm`'s POSITIVE path for
/// reset-password/verify-email (and `sendOtp`/`sendMagicLink` entirely) all
/// require a secret this driver has no way to observe -- in a COMPILED
/// binary (`kIsCompiled == true`, which is what this harness always runs)
/// the secret is 32 random bytes embedded only in the body of an email
/// `courier.send()` never delivers anywhere this driver can read (see
/// apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/reset_password.dart and
/// verify_email.dart). What IS covered below is the send half (200, then a
/// rate limit on a second send) and confirm's NEGATIVE path (a garbage
/// token is rejected, not 500s).
Future<void> _authSurface(Api api) async {
  // -- refresh --------------------------------------------------------------
  final refreshEmail = 'e2e-refresh@example.com';
  final refreshSignUp = await api.signUp(
    table: 'admins',
    email: refreshEmail,
    password: 'e2e-refresh-password-1',
  );
  final oldToken = refreshSignUp['accessToken'] as String;
  final refreshRes = await api._sendRaw(
    'POST',
    '/auth/refresh',
    authorization: oldToken,
  );
  api.expect(
    'POST /auth/refresh answers 2xx for a live token',
    actual: refreshRes.status >= 200 && refreshRes.status < 300,
    expected: true,
  );
  final newToken = (refreshRes.data as Map?)?['accessToken'] as String?;
  api.expect(
    'refresh hands back a NEW access token',
    actual: newToken != null && newToken != oldToken,
    expected: true,
  );
  final oldTokenRefreshAgain = await api._sendRaw(
    'POST',
    '/auth/refresh',
    authorization: oldToken,
  );
  api.expect(
    'the OLD token is revoked once refreshed -- it cannot refresh again',
    actual: oldTokenRefreshAgain.status,
    expected: 401,
    why:
        'a refresh that left the old token alive would let a caller hold two '
        'live sessions from one refresh call, which defeats the point of '
        'rotating the token at all.',
  );

  // -- reset-password: send, then rate-limited on a second send ------------
  final resetEmail = 'e2e-reset@example.com';
  await api.signUp(
    table: 'admins',
    email: resetEmail,
    password: 'e2e-reset-password-1',
  );
  final resetSend1 = await api._sendRaw(
    'POST',
    '/auth/reset-password',
    body: {'type': 'sendResetPassword', 'table': 'admins', 'email': resetEmail},
  );
  api.expect(
    'POST /auth/reset-password answers 2xx the first time',
    actual: resetSend1.status >= 200 && resetSend1.status < 300,
    expected: true,
  );
  final resetSend2 = await api._sendRaw(
    'POST',
    '/auth/reset-password',
    body: {'type': 'sendResetPassword', 'table': 'admins', 'email': resetEmail},
  );
  api.expect(
    'a second reset-password send inside the cooldown is rate-limited',
    actual: resetSend2.status,
    expected: 429,
    why:
        'without a cooldown a caller could re-trigger delivery (and burn '
        "whatever the email provider bills per send) as fast as it can POST.",
  );

  // -- verify-email: send (requires an authenticated caller) ---------------
  final verifyEmailAddr = 'e2e-verify@example.com';
  final verifySignUp = await api.signUp(
    table: 'admins',
    email: verifyEmailAddr,
    password: 'e2e-verify-password-1',
  );
  final verifySend = await api._sendRaw(
    'POST',
    '/auth/verify-email',
    authorization: verifySignUp['accessToken'] as String,
    body: {'table': 'admins', 'email': verifyEmailAddr},
  );
  api.expect(
    'POST /auth/verify-email answers 2xx for an authenticated caller',
    actual: verifySend.status >= 200 && verifySend.status < 300,
    expected: true,
  );
  final verifySendUnauth = await api._sendRaw('POST', '/auth/verify-email');
  api.expect(
    'POST /auth/verify-email refuses an unauthenticated caller',
    actual: verifySendUnauth.status >= 400,
    expected: true,
  );

  // -- confirm: negative path only (see the doc comment above) -------------
  final garbageToken = base64Encode(
    utf8.encode('not-a-real-secret:nobody@example.com'),
  );
  final confirmBad = await api._sendRaw(
    'POST',
    '/auth/confirm',
    body: {
      'type': 'confirmResetPassword',
      'token': garbageToken,
      'newPassword': 'whatever-new-password-1',
    },
  );
  api.expect(
    'POST /auth/confirm rejects a token it never issued',
    actual: confirmBad.status >= 400 && confirmBad.status < 500,
    expected: true,
    why:
        'a token this driver invented should never be treated as valid -- a '
        '2xx here would mean anyone could reset any password by guessing.',
  );

  // -- admin sign-in via the dedicated /auth/admin route --------------------
  final adminRouteEmail = 'e2e-admin-route@example.com';
  const adminRoutePassword = 'e2e-admin-route-password-1';
  await api.signUp(
    table: 'admins',
    email: adminRouteEmail,
    password: adminRoutePassword,
  );
  final adminRouteSignIn = await api._sendRaw(
    'POST',
    '/auth/admin',
    body: {
      'type': 'adminSignIn',
      'email': adminRouteEmail,
      'password': adminRoutePassword,
    },
  );
  api.expect(
    'POST /auth/admin signs in independently of /auth/sign-in',
    actual: (adminRouteSignIn.data as Map?)?['accessToken'] != null,
    expected: true,
  );

  // -- logout / logout-all ---------------------------------------------------
  final logoutEmail = 'e2e-logout@example.com';
  final logoutSignUp = await api.signUp(
    table: 'admins',
    email: logoutEmail,
    password: 'e2e-logout-password-1',
  );
  final logoutToken = logoutSignUp['accessToken'] as String;
  final logoutRes = await api._sendRaw(
    'DELETE',
    '/auth',
    authorization: logoutToken,
  );
  api.expect(
    'DELETE /auth (logout) answers 2xx',
    actual: logoutRes.status >= 200 && logoutRes.status < 300,
    expected: true,
  );
  final refreshAfterLogout = await api._sendRaw(
    'POST',
    '/auth/refresh',
    authorization: logoutToken,
  );
  api.expect(
    'a logged-out token can no longer refresh',
    actual: refreshAfterLogout.status,
    expected: 401,
  );

  final logoutAllEmail = 'e2e-logout-all@example.com';
  const logoutAllPassword = 'e2e-logout-all-password-1';
  final logoutAllSession1 = await api.signUp(
    table: 'admins',
    email: logoutAllEmail,
    password: logoutAllPassword,
  );
  final logoutAllSession2 = await api.signIn(
    table: 'admins',
    email: logoutAllEmail,
    password: logoutAllPassword,
  );
  final logoutAllRes = await api._sendRaw(
    'DELETE',
    '/auth/all',
    authorization: logoutAllSession1['accessToken'] as String,
  );
  api.expect(
    'DELETE /auth/all answers 2xx',
    actual: logoutAllRes.status >= 200 && logoutAllRes.status < 300,
    expected: true,
  );
  final session2AfterLogoutAll = await api._sendRaw(
    'POST',
    '/auth/refresh',
    authorization: logoutAllSession2['accessToken'] as String,
  );
  api.expect(
    'logout-all revokes a DIFFERENT session for the same account too',
    actual: session2AfterLogoutAll.status,
    expected: 401,
    why:
        'logout-all that only touched the session that called it would be '
        'indistinguishable from plain logout -- this is the one assertion '
        'that tells them apart.',
  );

  // -- the generic, multiplexed POST /auth -----------------------------------
  //
  // A DIFFERENT controller method (AuthHandler.authenticate) from the one
  // POST /auth/sign-in uses (AuthHandler.signIn) -- proven working above and
  // below respectively does not prove this one parses the same body.
  final genericEmail = 'e2e-generic-auth@example.com';
  const genericPassword = 'e2e-generic-auth-password-1';
  await api.signUp(
    table: 'admins',
    email: genericEmail,
    password: genericPassword,
  );
  final genericSignIn = await api._sendRaw(
    'POST',
    '/auth',
    body: {
      'type': 'signIn',
      'table': 'admins',
      'email': genericEmail,
      'password': genericPassword,
    },
  );
  api.expect(
    'POST /auth with type=signIn reaches the same result as /auth/sign-in',
    actual: (genericSignIn.data as Map?)?['accessToken'] != null,
    expected: true,
  );
}

/// `GET /health`, `GET /dashboard/metrics`, `GET /crons/list`,
/// `POST /crons/run`, `POST /email` -- all admin/operational surface, none
/// of it table-scoped so none of it needs its own fixture rows.
Future<void> _operationalSurface(Api api) async {
  final health = await api._sendRaw('GET', '/health');
  api.expect('GET /health answers 2xx', actual: health.status, expected: 200);

  final adminEmail = 'e2e-ops-admin@example.com';
  final adminSignUp = await api.signUp(
    table: 'admins',
    email: adminEmail,
    password: 'e2e-ops-admin-password-1',
  );
  final adminToken = adminSignUp['accessToken'] as String;

  final metrics = await api._sendRaw(
    'GET',
    '/dashboard/metrics',
    authorization: adminToken,
  );
  api.expect(
    'GET /dashboard/metrics answers 2xx for an admin',
    actual: metrics.status,
    expected: 200,
  );
  final metricsBody = metrics.data as Map?;
  api.expect(
    'the metrics body carries the fields the dashboard UI reads',
    actual:
        metricsBody != null &&
        metricsBody.containsKey('request_count_24h') &&
        metricsBody.containsKey('active_sessions'),
    expected: true,
  );

  final nonAdminEmail = 'e2e-ops-nonadmin@example.com';
  final nonAdminSignUp = await api.signUp(
    table: 'users',
    email: nonAdminEmail,
    password: 'e2e-ops-nonadmin-password-1',
  );
  final metricsAsNonAdmin = await api._sendRaw(
    'GET',
    '/dashboard/metrics',
    authorization: nonAdminSignUp['accessToken'] as String,
  );
  api.expect(
    'GET /dashboard/metrics is hidden from a non-admin, not just filtered',
    actual: metricsAsNonAdmin.status,
    expected: 403,
  );

  final cronList = await api._sendRaw(
    'GET',
    '/crons/list',
    authorization: adminToken,
  );
  api.expect(
    'GET /crons/list answers 2xx for an admin',
    actual: cronList.status,
    expected: 200,
  );
  final cronNames = ((cronList.data as Map?)?['names'] as List?)
      ?.cast<String>();
  api.expect(
    'the internal cleanup crons every zonai app carries are listed',
    actual: cronNames?.contains('_delete_expired_jwts'),
    expected: true,
    why:
        'this fixture registers no crons of its own -- the built-in internal '
        'ones (delete_expired_jwts, cleanup_logs, ...) are the only way to '
        'exercise this route without adding a crons/ file just for the test.',
  );

  final cronListAsNonAdmin = await api._sendRaw(
    'GET',
    '/crons/list',
    authorization: nonAdminSignUp['accessToken'] as String,
  );
  api.expect(
    'GET /crons/list is hidden from a non-admin',
    actual: cronListAsNonAdmin.status,
    expected: 403,
  );

  final cronRun = await api._sendRaw(
    'POST',
    '/crons/run?name=_delete_expired_jwts',
    authorization: adminToken,
  );
  api.expect(
    'POST /crons/run answers 2xx for a real, internal cron name',
    actual: cronRun.status >= 200 && cronRun.status < 300,
    expected: true,
  );

  final emailSend = await api._sendRaw(
    'POST',
    '/email',
    body: {
      'to': {'address': 'e2e-email-recipient@example.com'},
      'subject': 'e2e probe',
      'template': 'otp_code',
      'variables': {'otp': '000000'},
    },
  );
  api.expect(
    'POST /email answers 2xx for a real built-in template',
    actual: emailSend.status >= 200 && emailSend.status < 300,
    expected: true,
    why:
        'the payload shape matters here: `to` is a single object (not a '
        'list) and `template` names a real template file -- either mistake '
        'is a 500, which this assertion would also have caught.',
  );
}

/// `GET/POST/PATCH/DELETE /img/:id` -- the internal `_photos` table's HTTP
/// surface. Genuinely a different domain from `/db`: raw bytes in and out,
/// not JSON, and ownership-based row rules (create needs any authenticated
/// caller; update/delete need the owner or an admin) rather than this
/// fixture's own table rules.
///
/// NOT covered: a restart-durability re-check in `verify` phase. The
/// `_photos` table's id is server-generated (`Id.generate('ph')`, see
/// apps/zonai/lib/src/db_mutator/zonai_db/parts/photo.dart) and returned
/// only in the create response -- `verify` runs as a SEPARATE process
/// against a SEPARATE drive.dart invocation with no way to recover that id,
/// unlike this file's other fixtures which use client-supplied ids for
/// exactly this reason.
Future<void> _photoSurface(Api api) async {
  final ownerSignUp = await api.signUp(
    table: 'users',
    email: 'e2e-photo-owner@example.com',
    password: 'e2e-photo-owner-password-1',
  );
  final ownerToken = ownerSignUp['accessToken'] as String;
  final strangerSignUp = await api.signUp(
    table: 'users',
    email: 'e2e-photo-stranger@example.com',
    password: 'e2e-photo-stranger-password-1',
  );
  final strangerToken = strangerSignUp['accessToken'] as String;

  final created = await api.createPhoto(
    table: 'admins',
    bytes: _kTestPng1x1,
    contentType: 'image/png',
    authorization: ownerToken,
  );
  api.expect('POST /img answers 2xx', actual: created.status, expected: 200);
  final createdBody = jsonDecode(utf8.decode(created.bytes)) as Map;
  final photoId = (createdBody['data'] as Map)['id'] as String;

  final viewed = await api.viewPhoto(photoId, authorization: ownerToken);
  api.expect(
    'GET /img/:id answers 2xx with the exact bytes just uploaded',
    actual: [viewed.status, _bytesEqual(viewed.bytes, _kTestPng1x1)],
    expected: [200, true],
  );
  api.expect(
    'the response is served with an image content-type, not a generic one',
    actual: viewed.contentType,
    expected: 'image/png',
  );

  // create a second photo owned by the stranger -- the "untouched" subject
  // for the update/delete assertions below.
  final strangersPhoto = await api.createPhoto(
    table: 'admins',
    bytes: _kTestPng1x1,
    contentType: 'image/png',
    authorization: strangerToken,
  );
  final strangersPhotoId =
      ((jsonDecode(utf8.decode(strangersPhoto.bytes)) as Map)['data']
              as Map)['id']
          as String;

  final strangerUpdateAttempt = await api.updatePhoto(
    id: photoId,
    bytes: _kTestPng1x1Alt,
    contentType: 'image/png',
    authorization: strangerToken,
  );
  api.expect(
    "a non-owner cannot PATCH someone else's photo",
    actual: strangerUpdateAttempt.status,
    expected: 403,
  );

  final ownerUpdate = await api.updatePhoto(
    id: photoId,
    bytes: _kTestPng1x1Alt,
    contentType: 'image/png',
    authorization: ownerToken,
  );
  api.expect(
    'PATCH /img/:id answers 2xx for the owner',
    actual: ownerUpdate.status,
    expected: 200,
  );
  final viewedAfterUpdate = await api.viewPhoto(
    photoId,
    authorization: ownerToken,
  );
  api.expect(
    'the updated bytes are what a subsequent view returns',
    actual: _bytesEqual(viewedAfterUpdate.bytes, _kTestPng1x1Alt),
    expected: true,
  );

  final strangerDeleteAttempt = await api.deletePhoto(
    photoId,
    authorization: strangerToken,
  );
  api.expect(
    "a non-owner cannot DELETE someone else's photo",
    actual: strangerDeleteAttempt.status,
    expected: 403,
  );

  final ownerDelete = await api.deletePhoto(photoId, authorization: ownerToken);
  api.expect(
    'DELETE /img/:id answers 2xx for the owner',
    actual: ownerDelete.status,
    expected: 200,
  );

  final viewAfterDelete = await api.viewPhoto(
    photoId,
    authorization: ownerToken,
  );
  api.expect(
    'the deleted photo is gone',
    actual: viewAfterDelete.status,
    expected: 404,
  );

  final strangersPhotoStillThere = await api.viewPhoto(
    strangersPhotoId,
    authorization: strangerToken,
  );
  api.expect(
    "deleting the owner's photo did not take the stranger's photo with it",
    actual: [
      strangersPhotoStillThere.status,
      _bytesEqual(strangersPhotoStillThere.bytes, _kTestPng1x1),
    ],
    expected: [200, true],
    why:
        "if delete's row scoping were wrong (matching on something broader "
        "than the one id), the stranger's unrelated photo would vanish too.",
  );
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A minimal valid 1x1 PNG (the server sniffs real image bytes, not just the
/// declared content-type header, so an arbitrary byte string 400s).
final _kTestPng1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

/// A second, distinct valid 1x1 PNG (different pixel colour) -- for the
/// update assertions, so "bytes changed" and "bytes are still a valid PNG"
/// are both true without reusing the create fixture's bytes.
final _kTestPng1x1Alt = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// An extension's write must land. `onSignUp` backfills the matching invite's
/// `user_id`; the report this fixture was built from was "onSignUp never
/// persists its writes".
Future<void> _signupBackfill(Api api, String phase) async {
  const invitedEmail = 'invited@example.com';
  const otherEmail = 'not-invited@example.com';
  const password = 'signup-backfill-password-1';

  if (phase == 'verify') {
    final row = await api.get('invites', _eq('id', 'inv-1'));
    api.expect(
      "the extension's write is still there after a server restart",
      actual: row['user_id'] != null,
      expected: true,
      why:
          'an extension runs in a worker and its mutation is scheduled back to '
          'the host. A write that is applied to an in-memory row and never '
          'committed reads correctly until the process ends.',
    );
    return;
  }

  await api.create('invites', {'id': 'inv-1', 'email': invitedEmail});
  await api.create('invites', {'id': 'inv-2', 'email': otherEmail});

  await api.mutation(
    name: "sign-up runs the AuthExtension and its mutate.update lands",
    why:
        'the extension calls get.one on another table and then '
        'mutate.update.one. Both cross the worker boundary.',
    mutate: () =>
        api.signUp(table: 'users', email: invitedEmail, password: password),
    response: (res) => api.expect(
      'sign-up succeeded',
      actual: res['accessToken'] != null,
      expected: true,
    ),
    refetchById: () async {
      // The extension's write is asynchronous relative to the sign-up
      // response, so this is the one place the suite waits for a value rather
      // than reading once. It fails on timeout, not on the first read.
      final row = await api.eventually(
        'the invite for the signed-up email has its user_id backfilled',
        read: () => api.get('invites', _eq('id', 'inv-1')),
        until: (row) => row['user_id'] != null,
      );
      api.expect(
        'the backfilled user_id is a real id, not an empty string',
        actual: (row['user_id'] as String?)?.isNotEmpty,
        expected: true,
      );
    },
    untouched: () async {
      final row = await api.get('invites', _eq('id', 'inv-2'));
      api.expect(
        "the invite for a different email was not backfilled",
        actual: row['user_id'],
        expected: null,
        why:
            "the extension's where is Eq('email', user.email). A clause "
            'matching too much backfills every invite with the same id and '
            'every other assertion here still passes.',
      );
    },
  );
}

/// Concurrent traffic through one compiled binary: the fixture is named for the
/// report that concurrent list/create interleaved badly.
///
/// This suite found a live zonai bug on its first run -- a burst of concurrent
/// creates raced the rate limiter's own counter row into 500s instead of
/// 429s, now fixed (see the "never answers 5xx" assertion below, which used
/// to be a knownFailure()). Whether any individual request is rejected is
/// still a race, so this cannot gate on "every create succeeds". What it CAN
/// gate on, whatever the rate limiter did, is that the database agrees with
/// the responses: the number of committed rows equals the number of creates
/// that answered 2xx, no more and no less. A write that was reported and not
/// committed, or committed and not reported, fails that regardless of how
/// many requests were rejected.
Future<void> _concurrency(Api api, String phase) async {
  const total = 24;
  const readers = 8;

  if (phase == 'verify') {
    // The exact row count is a function of how the race went in `seed`, so it
    // is not a constant here. What must hold across a restart is that every
    // row that IS there is intact and unique -- a torn or duplicated write is
    // what a concurrent create path gets wrong.
    final rows = await api.list('items');
    final ids = rows.map((r) => r['id']).toList();
    api.expect(
      'the concurrently created rows survive a server restart',
      actual: ids.isNotEmpty,
      expected: true,
    );
    api.expect(
      'no row was duplicated by the concurrent creates',
      actual: ids.length,
      expected: ids.toSet().length,
    );
    api.expect(
      'every surviving row is intact (name still matches id)',
      actual: rows.every((r) => r['name'] == r['id']),
      expected: true,
      why:
          'interleaved writes that crossed rows would show up here as a name '
          'belonging to a different id.',
    );
    api.expect(
      'count agrees with list after the restart',
      actual: await api.count('items'),
      expected: ids.length,
    );
    return;
  }

  // The burst. `createRaw`/`listRaw` rather than `create`/`list` because the
  // status codes are part of the subject here, and a 5xx would otherwise abort
  // before any of the correctness assertions below ran.
  final creates = await Future.wait([
    for (var i = 0; i < total; i++)
      api.createRaw('items', {'id': 'item-$i', 'name': 'item-$i'}),
  ]);
  final lists = await Future.wait([
    for (var i = 0; i < readers; i++) api.listRaw('items'),
  ]);

  final failedCreates = creates.where((r) => r.status >= 500).length;
  final failedReads = lists.where((r) => r.status >= 500).length;

  // Was a knownFailure() -- see git history on this line for the incident
  // report -- until RateLimiter.check (apps/zonai/lib/src/services/
  // rate_limiter.dart) stopped racing its own bucket row. It used to read
  // the (client_ip, table, operation) counter row and INSERT it when
  // absent, retrying ONCE on a unique-index conflict and rethrowing on the
  // second one -- which surfaced as an uncaught 500, not the 429 rate
  // limiting is supposed to produce, once enough concurrent requests raced
  // the same bucket that a single retry could not observe the winner's row
  // in time (reads and writes used separate sqlite connections). The fix
  // wraps the whole read-then-write in `db.transaction`, which runs on the
  // single writer connection and holds the writer lock for the entire body,
  // so no two `check()` calls for any bucket can interleave at all -- no
  // retry loop is needed because there is no longer a race to lose.
  api.expect(
    'a burst of concurrent requests never answers 5xx',
    actual:
        '$failedCreates of $total creates and $failedReads of $readers reads '
        'answered 5xx',
    expected: '0 of $total creates and 0 of $readers reads answered 5xx',
    why:
        'a 500 here is indistinguishable from a server fault -- the caller '
        'cannot tell it should back off, and any retry policy hammers a '
        'server that is already struggling.',
  );

  // -- what gates, whatever the race did ----------------------------------
  final accepted = creates.where((r) => r.status == 200).toList();
  api.expect(
    'at least one concurrent create and one concurrent read got through',
    actual: [accepted.isNotEmpty, lists.any((r) => r.status == 200)],
    expected: [true, true],
    why:
        'without this, every assertion below vacuously passes on the day the '
        'server answers nothing at all.',
  );
  api.expect(
    'every accepted create echoed back the row it was given',
    actual: accepted.every((r) => r.row['name'] == r.row['id']),
    expected: true,
  );
  api.expect(
    'the database holds exactly the creates that were accepted',
    actual: await api.count('items'),
    expected: accepted.length,
    why:
        'the assertion this fixture exists for. A create that answered 2xx '
        'without committing, or committed twice, or committed under a '
        'rejected request, breaks this no matter how the rate limiter behaved.',
  );

  final committed = await api.list('items');
  api.expect(
    'the committed ids are exactly the accepted ids',
    actual: committed.map((r) => r['id'] as String).toList()..sort(),
    expected: accepted.map((r) => r.row['id'] as String).toList()..sort(),
  );

  for (var i = 0; i < lists.length; i++) {
    if (lists[i].status != 200) continue;
    final ids = lists[i].items.map((r) => r['id']).toList();
    api.expect(
      'concurrent list #$i returned no duplicate ids',
      actual: ids.length,
      expected: ids.toSet().length,
      why:
          'a read interleaved with writes must never see a row twice, however '
          'many rows it happened to catch.',
    );
    api.expect(
      'concurrent list #$i returned whole rows only',
      actual: lists[i].items.every(
        (r) => r['id'] != null && r['name'] != null && r['created_at'] != null,
      ),
      expected: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Where / Update wire helpers
//
// The canonical form is {"type": ..., "column": ..., "value": ...} -- except
// In/NotIn, which use "values" (plural). Getting that wrong is a 500 rather
// than a 400, so it is centralised here instead of spelled out per call site.
// ---------------------------------------------------------------------------

Map<String, Object?> _eq(String column, Object value) =>
    _cmp('eq', column, value);

Map<String, Object?> _cmp(String type, String column, Object value) => {
  'type': type,
  'column': column,
  'value': value,
};

Map<String, Object?> _inOp(String type, String column, List<Object> values) => {
  'type': type,
  'column': column,
  'values': values,
};

Map<String, Object?> _columnUpdate(String column, Object? value) => {
  'type': 'column',
  'column': column,
  'value': {'type': 'literal', 'value': value},
};

/// Boolean columns come back over the wire as `0`/`1`, not `false`/`true`.
bool _truthy(Object? value) => value == true || value == 1;

Future<void> _expectCodes(
  Api api,
  String name, {
  required Map<String, Object?> where,
  required List<String> expected,
  String? why,
}) async {
  final rows = await api.list('widgets', where: where, orderByColumn: 'code');
  api.expect(
    name,
    actual: rows.map((r) => r['code']).toList(),
    expected: expected,
    why: why,
  );
}

// ---------------------------------------------------------------------------
// The client
// ---------------------------------------------------------------------------

class Api {
  Api({required this.baseUrl, required this.fixture, required this.mode});

  final String baseUrl;
  final String fixture;
  final String mode;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  var passed = 0;
  var knownFailures = 0;

  void close() => _client.close(force: true);

  /// The three assertions every mutation owes, per docs/testing-strategy.md:
  /// the response body, the row refetched independently BY ID, and the rows
  /// that must NOT have changed.
  ///
  /// All three are required parameters on purpose. `a16b499` was a write that
  /// landed with a wrong response; an over-broad `where` is the mirror image.
  /// Neither is visible from the other two, so none of them is optional and
  /// the signature is what enforces that rather than a comment.
  Future<void> mutation({
    required String name,
    required String why,
    required Future<Map<String, Object?>> Function() mutate,
    required FutureOr<void> Function(Map<String, Object?> response) response,
    required FutureOr<void> Function() refetchById,
    required FutureOr<void> Function() untouched,
  }) async {
    stdout.writeln('  mutation: $name');
    final res = await mutate();
    await response(res);
    await refetchById();
    await untouched();
  }

  /// Reads until [until] holds or the deadline passes. Only for values a
  /// worker writes back asynchronously; a read that should already be correct
  /// uses [get] so a slow-but-wrong path cannot be papered over by waiting.
  Future<Map<String, Object?>> eventually(
    String name, {
    required Future<Map<String, Object?>> Function() read,
    required bool Function(Map<String, Object?> row) until,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, Object?> last = const {};
    while (DateTime.now().isBefore(deadline)) {
      last = await read();
      if (until(last)) {
        passed++;
        stdout.writeln('  ok: $name');
        return last;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    fail(
      name,
      expected: 'the condition to hold within ${timeout.inSeconds}s',
      actual: jsonEncode(last),
    );
  }

  /// A real product bug this layer found and does not fix.
  ///
  /// It reports on EVERY run and gates nothing, because the alternatives are
  /// both worse: a red gate cannot be turned on, and deleting the assertion
  /// deletes the finding. [found] records when and where, so the entry carries
  /// its own date rather than relying on git blame.
  ///
  /// It also cannot rot the way `verify.yaml`'s exemptions did (see
  /// docs/testing-strategy.md Part 3): the day the bug is fixed this prints
  /// "NOW PASSES" and says to delete it. Nothing has to remember to re-ask.
  void knownFailure(
    String name, {
    required Object? actual,
    required Object? expected,
    required String found,
    required String why,
  }) {
    if (_deepEquals(actual, expected)) {
      passed++;
      stdout.writeln('  KNOWN FAILURE NOW PASSES: $name');
      stdout.writeln(
        '    -> the bug is gone. Delete this knownFailure() in '
        'tool/ci/e2e/drive.dart and let it gate.',
      );
      return;
    }

    knownFailures++;
    stderr.writeln('');
    stderr.writeln('  KNOWN FAILURE (reported, does NOT fail the run)');
    stderr.writeln('    fixture:   $fixture');
    stderr.writeln('    mode:      $mode');
    stderr.writeln('    assertion: $name');
    stderr.writeln('    expected:  ${_show(expected)}');
    stderr.writeln('    actual:    ${_show(actual)}');
    stderr.writeln('    found:     $found');
    for (final line in _wrap(why, 66)) {
      stderr.writeln('      $line');
    }
    stderr.writeln('');
  }

  void expect(
    String name, {
    required Object? actual,
    required Object? expected,
    String? why,
  }) {
    if (!_deepEquals(actual, expected)) {
      fail(name, expected: _show(expected), actual: _show(actual), why: why);
    }
    passed++;
    stdout.writeln('  ok: $name');
  }

  Never fail(
    String assertion, {
    required Object? expected,
    required Object? actual,
    String? why,
  }) {
    stderr.writeln('');
    stderr.writeln('E2E FAIL');
    stderr.writeln('  fixture:   $fixture');
    stderr.writeln('  mode:      $mode');
    stderr.writeln('  assertion: $assertion');
    stderr.writeln('  expected:  $expected');
    stderr.writeln('  actual:    $actual');
    if (why != null) {
      stderr.writeln('  why it is here:');
      for (final line in _wrap(why, 68)) {
        stderr.writeln('    $line');
      }
    }
    stderr.writeln('');
    close();
    exit(1);
  }

  // -- verbs --------------------------------------------------------------

  Future<Map<String, Object?>> get(
    String table,
    Map<String, Object?> where, {
    String? authorization,
  }) async {
    final res = await _send(
      'GET',
      '/db',
      query: {'table': table, 'where': where, 'expand': <String>[]},
      authorization: authorization,
    );
    _requireOk(res, 'GET /db table=$table');
    return _asMap(res.data);
  }

  Future<Map<String, Object?>> getExpectingStatus(
    String table,
    Map<String, Object?> where, {
    required int expectedStatus,
    String? authorization,
  }) async {
    final res = await _send(
      'GET',
      '/db',
      query: {'table': table, 'where': where, 'expand': <String>[]},
      authorization: authorization,
    );
    if (res.status != expectedStatus) {
      fail(
        'GET /db table=$table answers $expectedStatus',
        expected: expectedStatus,
        actual: '${res.status}: ${res.body}',
      );
    }
    return {'status': res.status, 'body': res.body};
  }

  Future<List<Map<String, Object?>>> list(
    String table, {
    Map<String, Object?>? where,
    String? orderByColumn,
    String? authorization,
  }) async {
    final res = await _send(
      'GET',
      '/db/list',
      query: {
        'table': table,
        if (where != null) 'where': where,
        if (orderByColumn != null)
          'order_by': [
            {'column': orderByColumn},
          ],
        'expand': <String>[],
      },
      authorization: authorization,
    );
    _requireOk(res, 'GET /db/list table=$table');
    final data = _asMap(res.data);
    final items = data['items'];
    if (items is! List) {
      fail(
        'GET /db/list table=$table returns an items list',
        expected: 'a list under "items"',
        actual: res.body,
      );
    }
    return [for (final item in items) _asMap(item)];
  }

  /// [create] without the 2xx requirement. `row` is empty on a non-200.
  Future<CreateResult> createRaw(
    String table,
    Map<String, Object?> object,
  ) async {
    final res = await _send(
      'POST',
      '/db',
      body: {'table': table, 'object': object},
    );
    return CreateResult(
      status: res.status,
      row: res.status == 200 && res.data is Map
          ? _asMap(res.data)
          : const <String, Object?>{},
      body: res.body,
    );
  }

  /// [list] without the 2xx requirement, for the cases where the status code
  /// is itself the subject. `items` is empty on a non-200.
  Future<ListResult> listRaw(String table) async {
    final res = await _send(
      'GET',
      '/db/list',
      query: {'table': table, 'expand': <String>[]},
    );
    if (res.status != 200) {
      return ListResult(status: res.status, items: const [], body: res.body);
    }
    final data = res.data;
    final items = data is Map ? data['items'] : null;
    return ListResult(
      status: res.status,
      items: items is List
          ? [for (final item in items) _asMap(item)]
          : const [],
      body: res.body,
    );
  }

  Future<int> count(String table, {Map<String, Object?>? where}) async {
    final res = await _send(
      'GET',
      '/db/count',
      query: {'table': table, if (where != null) 'where': where},
    );
    _requireOk(res, 'GET /db/count table=$table');
    final data = res.data;
    if (data is! int) {
      fail(
        'GET /db/count table=$table returns an int',
        expected: 'an int',
        actual: res.body,
      );
    }
    return data;
  }

  Future<Map<String, Object?>> create(
    String table,
    Map<String, Object?> object, {
    String? authorization,
  }) async {
    final res = await _send(
      'POST',
      '/db',
      body: {'table': table, 'object': object},
      authorization: authorization,
    );
    _requireOk(res, 'POST /db table=$table object=${jsonEncode(object)}');
    return _asMap(res.data);
  }

  Future<Map<String, Object?>> patchOne(
    String table, {
    required Map<String, Object?> where,
    required List<Map<String, Object?>> updates,
    String? authorization,
  }) async {
    final res = await _send(
      'PATCH',
      '/db',
      body: {'table': table, 'where': where, 'updates': updates},
      authorization: authorization,
    );
    _requireOk(res, 'PATCH /db table=$table where=${jsonEncode(where)}');
    return _asMap(res.data);
  }

  Future<Map<String, Object?>> patchOneExpectingStatus(
    String table, {
    required Map<String, Object?> where,
    required List<Map<String, Object?>> updates,
    required int expectedStatus,
    String? authorization,
  }) async {
    final res = await _send(
      'PATCH',
      '/db',
      body: {'table': table, 'where': where, 'updates': updates},
      authorization: authorization,
    );
    if (res.status != expectedStatus) {
      fail(
        'PATCH /db table=$table answers $expectedStatus',
        expected: expectedStatus,
        actual: '${res.status}: ${res.body}',
      );
    }
    return {'status': res.status, 'body': res.body};
  }

  /// Returns `{'rows': [...]}` -- `/db/many` answers with a list, and
  /// [mutation] hands its `response` callback a map.
  Future<Map<String, Object?>> patchMany(
    String table, {
    required Map<String, Object?> where,
    required List<Map<String, Object?>> updates,
    String? authorization,
  }) async {
    final res = await _send(
      'PATCH',
      '/db/many',
      body: {'table': table, 'where': where, 'updates': updates},
      authorization: authorization,
    );
    _requireOk(res, 'PATCH /db/many table=$table');
    final data = res.data;
    if (data is! List) {
      fail(
        'PATCH /db/many table=$table returns a list of rows',
        expected: 'a list',
        actual: res.body,
      );
    }
    return {
      'rows': [for (final row in data) _asMap(row)],
    };
  }

  Future<Map<String, Object?>> deleteOne(
    String table, {
    required Map<String, Object?> where,
    String? authorization,
  }) async {
    final res = await _send(
      'DELETE',
      '/db',
      body: {'table': table, 'where': where},
      authorization: authorization,
    );
    _requireOk(res, 'DELETE /db table=$table');
    return {'status': res.status};
  }

  Future<Map<String, Object?>> deleteMany(
    String table, {
    required Map<String, Object?> where,
    String? authorization,
  }) async {
    final res = await _send(
      'DELETE',
      '/db/many',
      body: {'table': table, 'where': where},
      authorization: authorization,
    );
    _requireOk(res, 'DELETE /db/many table=$table');
    return {'status': res.status};
  }

  Future<Map<String, Object?>> custom(
    String table, {
    required String operation,
    required Map<String, Object?> where,
    List<Map<String, Object?>> updates = const [],
    String? authorization,
  }) async {
    final res = await _send(
      'PATCH',
      '/db/custom/$operation',
      body: {'table': table, 'where': where, 'updates': updates},
      authorization: authorization,
    );
    _requireOk(res, 'PATCH /db/custom/$operation table=$table');
    return _asMap(res.data);
  }

  Future<Map<String, Object?>> customExpectingStatus(
    String table, {
    required String operation,
    Map<String, Object?>? where,
    bool many = false,
    required int expectedStatus,
    String? authorization,
  }) async {
    final res = await _send(
      'PATCH',
      '/db/custom/$operation${many ? '/many' : ''}',
      body: {'table': table, if (where != null) 'where': where, 'updates': []},
      authorization: authorization,
    );
    if (res.status != expectedStatus) {
      fail(
        'PATCH /db/custom/$operation table=$table answers $expectedStatus',
        expected: expectedStatus,
        actual: '${res.status}: ${res.body}',
      );
    }
    return {'status': res.status, 'body': res.body};
  }

  /// Returns `{'rows': [...]}`, same shape as [patchMany] -- `/many` answers
  /// with a list.
  Future<Map<String, Object?>> customMany(
    String table, {
    required String operation,
    Map<String, Object?>? where,
    List<Map<String, Object?>> updates = const [],
    String? authorization,
  }) async {
    final res = await _send(
      'PATCH',
      '/db/custom/$operation/many',
      body: {
        'table': table,
        if (where != null) 'where': where,
        'updates': updates,
      },
      authorization: authorization,
    );
    _requireOk(res, 'PATCH /db/custom/$operation/many table=$table');
    final data = res.data;
    if (data is! List) {
      fail(
        'PATCH /db/custom/$operation/many table=$table returns a list of rows',
        expected: 'a list',
        actual: res.body,
      );
    }
    return {
      'rows': [for (final row in data) _asMap(row)],
    };
  }

  /// Sentinel [nextStreamEvent] returns instead of throwing on a timeout or a
  /// stream that closed without producing anything -- both are legitimate
  /// outcomes the streaming assertions below need to tell apart from "an
  /// event with value null arrived".
  static final Object noStreamEvent = Object();

  /// Opens `GET <path>` with a JSON body (StreamBody/StreamListBody/
  /// StreamCountBody all travel this way, not as query params) and decodes
  /// each raw chunk the exact way the generated client does
  /// (zonai_client's db_data_source_impl.dart: `response.transform(utf8
  /// .decoder)`, one `jsonDecode` per chunk, no cross-chunk buffering, a
  /// chunk that isn't one whole JSON value is dropped rather than fatal).
  /// That is a real, load-bearing assumption of the shipped client -- testing
  /// it the same way validates the actual contract rather than a more
  /// forgiving one this driver could invent instead.
  Future<StreamSession> openStream(
    String path, {
    required Map<String, Object?> body,
    String? authorization,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = await _client.openUrl('GET', uri);
    request.followRedirects = false;
    if (authorization != null) {
      final value = authorization.toLowerCase().startsWith('bearer ')
          ? authorization
          : 'Bearer $authorization';
      request.headers.set(HttpHeaders.authorizationHeader, value);
    }
    final encoded = utf8.encode(jsonEncode(body));
    request.headers.contentType = ContentType.json;
    request.headers.contentLength = encoded.length;
    request.add(encoded);
    final response = await request.close();
    if (response.statusCode != 200) {
      final text = await response.transform(utf8.decoder).join();
      fail(
        'GET $path opens a stream',
        expected: 200,
        actual: '${response.statusCode}: $text',
      );
    }

    final events = StreamController<Object?>();
    final sub = response
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            try {
              final decoded = jsonDecode(chunk);
              if (decoded case {'data': final data}) {
                events.add(data);
              }
            } catch (_) {
              // Mirrors the generated client: a chunk that is not one whole JSON
              // value is dropped, not treated as fatal.
            }
          },
          onDone: () {
            if (!events.isClosed) events.close();
          },
          onError: (Object e, StackTrace st) {
            if (!events.isClosed) events.addError(e, st);
          },
          cancelOnError: false,
        );
    return StreamSession._(sub, events);
  }

  /// Waits up to [timeout] for the next event on [session]. Returns
  /// [noStreamEvent] on a timeout or a cleanly-closed-with-nothing stream,
  /// rather than throwing -- "nothing arrived" is exactly the outcome some
  /// of the assertions below expect to observe.
  Future<Object?> nextStreamEvent(
    StreamSession session, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await session.events.first.timeout(
        timeout,
        onTimeout: () => noStreamEvent,
      );
    } on StateError {
      return noStreamEvent;
    }
  }

  /// `POST /img` -- the meta travels as `?meta=<json>` (named after the
  /// handler's parameter, not the `body` convention `/db` uses for its own
  /// `@Query()` payloads), and the image is the raw request body, not JSON.
  Future<_BytesRes> createPhoto({
    required String table,
    required List<int> bytes,
    required String contentType,
    String? authorization,
  }) => _sendBytes(
    'POST',
    '/img',
    query: {
      'meta': {'table': table},
    },
    bytes: bytes,
    contentType: contentType,
    authorization: authorization,
  );

  Future<_BytesRes> updatePhoto({
    required String id,
    required List<int> bytes,
    required String contentType,
    String? authorization,
  }) => _sendBytes(
    'PATCH',
    '/img/$id',
    bytes: bytes,
    contentType: contentType,
    authorization: authorization,
  );

  Future<_BytesRes> viewPhoto(String id, {String? authorization}) =>
      _sendBytes('GET', '/img/$id', authorization: authorization);

  Future<_BytesRes> deletePhoto(String id, {String? authorization}) =>
      _sendBytes('DELETE', '/img/$id', authorization: authorization);

  Future<_BytesRes> _sendBytes(
    String method,
    String path, {
    Map<String, Object?>? query,
    List<int>? bytes,
    String? contentType,
    String? authorization,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query == null
          ? null
          : {
              for (final entry in query.entries)
                entry.key: jsonEncode(entry.value),
            },
    );
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    if (authorization != null) {
      final value = authorization.toLowerCase().startsWith('bearer ')
          ? authorization
          : 'Bearer $authorization';
      request.headers.set(HttpHeaders.authorizationHeader, value);
    }
    if (bytes != null) {
      if (contentType != null) request.headers.set('content-type', contentType);
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response
        .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk))
        .timeout(const Duration(seconds: 60));
    return _BytesRes(
      status: response.statusCode,
      bytes: body.takeBytes(),
      contentType: response.headers.contentType?.mimeType,
    );
  }

  Future<Map<String, Object?>> signUp({
    required String table,
    required String email,
    required String password,
  }) async {
    final res = await _send(
      'POST',
      '/auth/sign-up',
      body: {
        'type': 'signUp',
        'table': table,
        'email': email,
        'password': password,
      },
    );
    _requireOk(res, 'POST /auth/sign-up table=$table email=$email');
    return _asMap(res.data);
  }

  Future<Map<String, Object?>> signIn({
    required String table,
    required String email,
    required String password,
  }) async {
    final res = await _send(
      'POST',
      '/auth/sign-in',
      body: {
        'type': 'signIn',
        'table': table,
        'email': email,
        'password': password,
      },
    );
    _requireOk(res, 'POST /auth/sign-in table=$table email=$email');
    return _asMap(res.data);
  }

  /// Returns the status code, which must be >= 400. A sign-in that succeeds
  /// where it was supposed to be rejected fails here rather than being read
  /// as "no exception, so fine".
  Future<int> signInExpectingFailure({
    required String table,
    required String email,
    required String password,
  }) async {
    final res = await _send(
      'POST',
      '/auth/sign-in',
      body: {
        'type': 'signIn',
        'table': table,
        'email': email,
        'password': password,
      },
    );
    if (res.status < 400) {
      fail(
        'POST /auth/sign-in with the wrong password is rejected',
        expected: 'a 4xx',
        actual: '${res.status}: ${res.body}',
      );
    }
    return res.status;
  }

  // -- transport ----------------------------------------------------------

  /// A plain HTTP call for routes outside `/db`'s `{'body': jsonEncode(...)}`
  /// query-param convention -- [path] may already carry its own query
  /// string (`/crons/run?name=...`), and [body], when given, is sent
  /// literally as the JSON request body rather than enveloped. Never throws
  /// on a non-2xx: callers here are asserting on status codes directly,
  /// including the negative-path ones.
  Future<_Res> _sendRaw(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? authorization,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    if (authorization != null) {
      final value = authorization.toLowerCase().startsWith('bearer ')
          ? authorization
          : 'Bearer $authorization';
      request.headers.set(HttpHeaders.authorizationHeader, value);
    }
    if (body != null) {
      final encoded = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 60));
    Object? data;
    if (text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        data = decoded is Map && decoded.containsKey('data')
            ? decoded['data']
            : decoded;
      } catch (_) {
        data = null;
      }
    }
    return _Res(status: response.statusCode, body: text, data: data);
  }

  void _requireOk(_Res res, String what) {
    if (res.status < 200 || res.status >= 300) {
      fail(
        what,
        expected: 'a 2xx',
        actual: '${res.status}: ${res.body}',
        why:
            'the request itself failed, so nothing below it was asserted. A '
            'harness that stopped at the exit code of the server process would '
            'not have seen this at all.',
      );
    }
  }

  Future<_Res> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    String? authorization,
  }) async {
    // GET bodies travel as a single JSON-encoded `body` query parameter --
    // the shape the generated client sends (see zonai_client's
    // db_data_source_impl.dart: `query: {'body': body}`).
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query == null ? null : {'body': jsonEncode(query)},
    );

    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    if (authorization != null) {
      // The `Bearer ` prefix is added here, once, because
      // `DbHandler._parseBearerAuthorization` returns NULL for a header
      // without it -- the request then proceeds as anonymous rather than
      // being rejected, so a call site that forgot the prefix gets a 403 on
      // the rule instead of a 401 on the token, and reads as a rules bug.
      final value = authorization.toLowerCase().startsWith('bearer ')
          ? authorization
          : 'Bearer $authorization';
      request.headers.set(HttpHeaders.authorizationHeader, value);
    }
    if (body != null) {
      final encoded = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = encoded.length;
      request.add(encoded);
    }

    final response = await request.close().timeout(const Duration(seconds: 60));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 60));

    Object? data;
    if (text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        data = decoded is Map && decoded.containsKey('data')
            ? decoded['data']
            : decoded;
      } catch (_) {
        data = null;
      }
    }
    return _Res(status: response.statusCode, body: text, data: data);
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    fail(
      'the response body is an object',
      expected: 'a JSON object',
      actual: _show(value),
    );
  }
}

class _Res {
  const _Res({required this.status, required this.body, required this.data});

  final int status;
  final String body;
  final Object? data;
}

class _BytesRes {
  const _BytesRes({
    required this.status,
    required this.bytes,
    required this.contentType,
  });

  final int status;
  final List<int> bytes;
  final String? contentType;
}

/// A live `GET`-with-body streaming connection opened by [Api.openStream].
class StreamSession {
  StreamSession._(this._subscription, this._events);

  final StreamSubscription<void> _subscription;
  final StreamController<Object?> _events;

  Stream<Object?> get events => _events.stream;

  /// Cancels the client-side subscription -- the trigger for the server's
  /// `onCancel` path (see the HybridStreamEngine/revali `asBroadcastStream`
  /// history this repo already has two leaks from).
  Future<void> close() async {
    await _subscription.cancel();
    if (!_events.isClosed) await _events.close();
  }
}

class ListResult {
  const ListResult({
    required this.status,
    required this.items,
    required this.body,
  });

  final int status;
  final List<Map<String, Object?>> items;
  final String body;
}

class CreateResult {
  const CreateResult({
    required this.status,
    required this.row,
    required this.body,
  });

  final int status;
  final Map<String, Object?> row;
  final String body;
}

// ---------------------------------------------------------------------------
// Small utilities
// ---------------------------------------------------------------------------

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    if (eq > 0) {
      out[arg.substring(2, eq)] = arg.substring(eq + 1);
    } else if (i + 1 < argv.length) {
      out[arg.substring(2)] = argv[++i];
    }
  }
  return out;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  // 0.5 read back from a REAL column is a double; a literal 1 from an INTEGER
  // column is an int. Comparing across the two is a wire-format detail, not a
  // finding.
  if (a is num && b is num) return a == b;
  return a == b;
}

String _show(Object? value) {
  if (value is String) return '"$value"';
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}

List<String> _wrap(String text, int width) {
  final words = text.split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}
