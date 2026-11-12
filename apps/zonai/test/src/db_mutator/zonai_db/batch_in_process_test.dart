import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/exceptions/hook_refused_exception.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger, Table;
import 'package:zonai_schema/zonai_schema.dart' as schema show Table;

import '../../../support/temp_directory.dart';

/// `ZonaiDb.batch` with rules and hooks in-process: every step lands or none
/// does, whichever step fails and whether it fails while being checked or
/// while its SQL runs.
void main() {
  late io.Directory projectRoot;
  late Settings settings;

  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }

    projectRoot = createCanonicalTempSync('zonai_batch_');
    io.Directory(
      p.join(projectRoot.path, '.zonai', 'migrations'),
    ).createSync(recursive: true);
    io.File(
      p.join(projectRoot.path, 'zonai.yaml'),
    ).writeAsStringSync('version: $kVersion\n');
    settings = runMergedScoped(
      () => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  });

  tearDownAll(() {
    HostWorkerRegistries.clear();
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  setUp(() {
    _hookCalls.clear();
    HostWorkerRegistries.operations = DbOperations(
      operations: [_OrgOperations(), _MemberOperations()],
      tables: [_orgs, _members],
    );
    HostWorkerRegistries.rules = DbRules(
      rules: [
        _OrgTableRules(),
        _OrgRowRules(),
        _MemberTableRules(),
        _MemberRowRules(),
      ],
    );
    HostWorkerRegistries.extensions = DbExtensions(
      extensions: [_OrgExtensions(), _MemberExtensions()],
    );
  });

  Future<void> run(Future<void> Function(ZonaiDb db) body) async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }
    await runMergedScopedFuture(
      () async {
        final db = ZonaiDb(configResolver: ConfigResolver.fixed(_config));
        try {
          final sql = await db.open();
          await sql.execute('DROP TABLE IF EXISTS "members"');
          await sql.execute('DROP TABLE IF EXISTS "orgs"');
          await sql.execute(
            'CREATE TABLE "orgs" ("id" TEXT PRIMARY KEY, '
            '"owner" TEXT NOT NULL)',
          );
          await sql.execute(
            'CREATE TABLE "members" ("id" TEXT PRIMARY KEY, '
            '"org" TEXT NOT NULL, "user" TEXT NOT NULL, '
            'UNIQUE ("org", "user"))',
          );
          await body(db);
        } finally {
          await db.dispose();
        }
      },
      override: {
        fsProvider.overrideWith(LocalFileSystem.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        settingsProvider.overrideWith(() => settings),
        processProvider,
        cleanUpProvider,
        executableStopProvider,
        migrateProvider,
      },
    );
  }

  Future<List<String>> state(ZonaiDb db) async {
    final sql = await db.open();
    final orgs = await sql.execute(
      'SELECT "id", "owner" FROM "orgs" ORDER BY "id"',
    );
    final members = await sql.execute(
      'SELECT "id", "org", "user" FROM "members" ORDER BY "id"',
    );
    return [
      for (final row in orgs.rows) 'org ${row[0]} owner=${row[1]}',
      for (final row in members.rows) 'member ${row[0]} ${row[1]}/${row[2]}',
    ];
  }

  /// One org `o1` owned by `u1`, with members `u1` and `u2`.
  Future<void> seed(ZonaiDb db) async {
    await db.create('orgs', CreatePayload(object: {'id': 'o1', 'owner': 'u1'}));
    await db.createMany(
      'members',
      CreateManyPayload(
        objects: [
          {'id': 'm1', 'org': 'o1', 'user': 'u1'},
          {'id': 'm2', 'org': 'o1', 'user': 'u2'},
        ],
      ),
    );
    _hookCalls.clear();
  }

  Future<Object?> capture(Future<Object?> Function() write) async {
    try {
      await write();
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  Future<List<BatchResult>> batch(ZonaiDb db, List<BatchOperation> ops) =>
      db.batch(BatchPayload(operations: ops));

  BatchOperation createOrg(String id, String owner) => BatchOperation.create(
    CreateBody(table: 'orgs', object: {'id': id, 'owner': owner}),
  );

  BatchOperation createMember(String id, String org, String user) =>
      BatchOperation.create(
        CreateBody(
          table: 'members',
          object: {'id': id, 'org': org, 'user': user},
        ),
      );

  test('every step lands, in order, and reports what it did', () async {
    await run((db) async {
      await seed(db);

      final results = await batch(db, [
        BatchOperation.update(
          UpdateOneBody(
            table: 'orgs',
            where: const Eq('id', 'o1'),
            updates: [
              Update.object(const {'owner': 'u2'}),
            ],
            expect: const Eq('owner', 'u1'),
          ),
        ),
        BatchOperation.createMany(
          const CreateManyBody(
            table: 'members',
            objects: [
              {'id': 'm3', 'org': 'o1', 'user': 'u3'},
            ],
          ),
        ),
        BatchOperation.updateMany(
          UpdateBody(
            table: 'members',
            where: const Eq('user', 'u2'),
            updates: [
              Update.object(const {'user': 'u9'}),
            ],
          ),
        ),
        const BatchOperation.delete(
          DeleteOneBody(table: 'members', where: Eq('id', 'm1')),
        ),
        const BatchOperation.deleteMany(
          DeleteBody(table: 'members', where: Eq('user', 'nobody')),
        ),
      ]);

      expect(
        [for (final r in results) '${r.op} ${r.table} ${r.count}'],
        [
          'update orgs 1',
          'createMany members 1',
          'updateMany members 1',
          'delete members 1',
          'deleteMany members 0',
        ],
      );
      expect(results[0].rows.single['owner'], 'u2');
      expect(results[1].rows.single['id'], 'm3');
      expect(results[2].rows.single['user'], 'u9');
      expect(results[3].rows, isEmpty);

      expect(await state(db), [
        'org o1 owner=u2',
        'member m2 o1/u9',
        'member m3 o1/u3',
      ]);
      expect(_hookCalls, [
        'before update orgs o1',
        'before create members m3',
        'before update members m2',
        'before delete members m1',
        'after update orgs o1',
        'after create members m3',
        'after update members m2',
        'after delete members m1',
      ]);
    });
  });

  test('a step whose SQL fails rolls back the steps before it', () async {
    await run((db) async {
      await seed(db);

      final failure = await capture(
        () => batch(db, [
          createOrg('o2', 'u1'),
          // Same org and user as m1: the unique index refuses it mid-way.
          createMember('m9', 'o1', 'u1'),
        ]),
      );

      expect(failure, isA<UniqueConstraintException>());
      expect(await state(db), [
        'org o1 owner=u1',
        'member m1 o1/u1',
        'member m2 o1/u2',
      ]);
      expect(
        _hookCalls.where((c) => c.startsWith('after')),
        isEmpty,
        reason: 'after hooks run only once the batch commits',
      );
    });
  });

  test('a step its row rules refuse writes nothing', () async {
    await run((db) async {
      final failure = await capture(
        () => batch(db, [
          createOrg('o1', 'u1'),
          createMember('m1', 'o1', 'denied'),
        ]),
      );

      expect(failure, isA<RowAccessDeniedException>());
      expect(await state(db), isEmpty);
    });
  });

  test('a step its before-hook refuses writes nothing', () async {
    await run((db) async {
      final failure = await capture(
        () => batch(db, [
          createOrg('o1', 'u1'),
          createMember('m1', 'o1', 'refuse'),
        ]),
      );

      expect(
        failure,
        isA<HookRefusedException>().having(
          (e) => e.error.code,
          'code',
          'member_refused',
        ),
      );
      expect(await state(db), isEmpty);
    });
  });

  test('a one-row update that matches nothing fails the batch with '
      'not-found', () async {
    await run((db) async {
      final failure = await capture(
        () => batch(db, [
          createOrg('o1', 'u1'),
          BatchOperation.update(
            UpdateOneBody(
              table: 'orgs',
              where: const Eq('id', 'missing'),
              updates: [
                Update.object(const {'owner': 'u2'}),
              ],
            ),
          ),
        ]),
      );

      expect(failure, isA<RecordNotFoundException>());
      expect(await state(db), isEmpty);
    });
  });

  test('a one-row delete that matches nothing fails the batch with '
      'not-found', () async {
    await run((db) async {
      final failure = await capture(
        () => batch(db, [
          createOrg('o1', 'u1'),
          const BatchOperation.delete(
            DeleteOneBody(table: 'members', where: Eq('id', 'missing')),
          ),
        ]),
      );

      expect(failure, isA<RecordNotFoundException>());
      expect(await state(db), isEmpty);
    });
  });

  test('an update whose expect does not hold writes nothing', () async {
    await run((db) async {
      await seed(db);

      final failure = await capture(
        () => batch(db, [
          createMember('m3', 'o1', 'u3'),
          BatchOperation.update(
            UpdateOneBody(
              table: 'orgs',
              where: const Eq('id', 'o1'),
              updates: [
                Update.object(const {'owner': 'u3'}),
              ],
              expect: const Eq('owner', 'someone-else'),
            ),
          ),
        ]),
      );

      expect(
        failure,
        isA<PreconditionFailedException>().having(
          (e) => e.current.single['owner'],
          'current owner',
          'u1',
        ),
      );
      expect(await state(db), [
        'org o1 owner=u1',
        'member m1 o1/u1',
        'member m2 o1/u2',
      ]);
    });
  });

  test('an update whose expect an earlier step broke rolls the batch '
      'back', () async {
    await run((db) async {
      await seed(db);

      // Both steps are checked against the org as it was (owner u1), so both
      // pass their checks. Inside the transaction the first moves the owner,
      // and the second's `expect` then matches nothing.
      final failure = await capture(
        () => batch(db, [
          BatchOperation.update(
            UpdateOneBody(
              table: 'orgs',
              where: const Eq('id', 'o1'),
              updates: [
                Update.object(const {'owner': 'u2'}),
              ],
            ),
          ),
          BatchOperation.update(
            UpdateOneBody(
              table: 'orgs',
              where: const Eq('id', 'o1'),
              updates: [
                Update.object(const {'owner': 'u3'}),
              ],
              expect: const Eq('owner', 'u1'),
            ),
          ),
        ]),
      );

      expect(failure, isA<PreconditionFailedException>());
      expect((await state(db)).first, 'org o1 owner=u1');
    });
  });

  test('later steps are checked against the database as it was before the '
      'batch', () async {
    await run((db) async {
      await seed(db);

      await batch(db, [
        createMember('m3', 'o1', 'u3'),
        BatchOperation.updateMany(
          UpdateBody(
            table: 'members',
            where: const Eq('org', 'o1'),
            updates: [
              Update.object(const {'org': 'o2'}),
            ],
          ),
        ),
      ]);

      // m3 did not exist when the updateMany picked its rows.
      expect(await state(db), [
        'org o1 owner=u1',
        'member m1 o2/u1',
        'member m2 o2/u2',
        'member m3 o1/u3',
      ]);
    });
  });

  test('an update of a row an earlier step deleted pairs before and after '
      'for its hook', () async {
    await run((db) async {
      await seed(db);

      final results = await batch(db, [
        const BatchOperation.delete(
          DeleteOneBody(table: 'members', where: Eq('id', 'm1')),
        ),
        BatchOperation.updateMany(
          UpdateBody(
            table: 'members',
            where: const Eq('org', 'o1'),
            updates: [
              Update.object(const {'user': 'x'}),
            ],
          ),
        ),
      ]);

      expect(results[1].count, 1);
      expect(_hookCalls, contains('after update members m2'));
      expect(await state(db), ['org o1 owner=u1', 'member m2 o1/x']);
    });
  });

  test('an empty batch writes nothing and returns nothing', () async {
    await run((db) async {
      expect(await batch(db, const []), isEmpty);
    });
  });

  test('a batch over the step limit is refused before anything runs', () async {
    await run((db) async {
      final failure = await capture(
        () => batch(db, [
          for (var i = 0; i <= BatchBody.maxOperations; i++)
            createOrg('o$i', 'u1'),
        ]),
      );

      expect(failure, isA<InvalidBodyException>());
      expect(await state(db), isEmpty);
    });
  });

  test('a batch that deletes photos is refused', () async {
    await run((db) async {
      final failure = await capture(
        () => batch(db, [
          createOrg('o1', 'u1'),
          const BatchOperation.deleteMany(
            DeleteBody(table: '_photos', where: Eq('id', 'p1')),
          ),
        ]),
      );

      expect(
        failure,
        isA<InvalidBodyException>().having(
          (e) => '$e',
          'message',
          contains('_photos'),
        ),
      );
      expect(await state(db), isEmpty);
    });
  });
}

final _hookCalls = <String>[];

const _config = AppConfig(
  appName: 'batch-fixture',
  passwordSecret: 'test-password-secret',
  jwtSecret: 'test-jwt-secret',
);

final class _TextId implements Id {
  const _TextId(this.value);

  @override
  final String value;

  @override
  String toString() => value;
}

final class _Org {
  _Org({required this.id, required this.owner});

  final _TextId id;
  final String owner;
}

final class _OrgTable extends schema.Table<_Org> {
  _OrgTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _TextId.new,
        generate: () => _TextId(Id.generate('org')),
      ),
      owner = $.text('owner', (s) => s.owner);

  @override
  _Org fromRow(RowReader read) => _Org(id: read(id), owner: read(owner));

  final IdColumn<_TextId> id;
  final TextColumn owner;
}

final _orgs = table('orgs', _OrgTable.new);

final class _Member {
  _Member({required this.id, required this.org, required this.user});

  final _TextId id;
  final String org;
  final String user;
}

final class _MemberTable extends schema.Table<_Member> {
  _MemberTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _TextId.new,
        generate: () => _TextId(Id.generate('mem')),
      ),
      org = $.text('org', (s) => s.org),
      user = $.text('user', (s) => s.user);

  @override
  _Member fromRow(RowReader read) =>
      _Member(id: read(id), org: read(org), user: read(user));

  final IdColumn<_TextId> id;
  final TextColumn org;
  final TextColumn user;
}

final _members = table('members', _MemberTable.new);

final class _OrgOperations extends TableOperations<_OrgTable, _Org> {
  _OrgOperations() : super(_orgs);
}

final class _MemberOperations extends TableOperations<_MemberTable, _Member> {
  _MemberOperations() : super(_members);
}

final class _OrgTableRules extends TableRules<_OrgTable, _Org> {
  _OrgTableRules() : super(_orgs);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;
}

final class _OrgRowRules extends RowRules<_OrgTable, _Org> {
  _OrgRowRules() : super(_orgs);

  @override
  Future<bool> canCreate(Jwt? jwt, _Org row) async => true;

  @override
  Future<bool> canView(Jwt? jwt, _Org row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, _Org before, _Org after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, _Org row) async => true;
}

final class _MemberTableRules extends TableRules<_MemberTable, _Member> {
  _MemberTableRules() : super(_members);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;
}

final class _MemberRowRules extends RowRules<_MemberTable, _Member> {
  _MemberRowRules() : super(_members);

  @override
  Future<bool> canCreate(Jwt? jwt, _Member row) async => row.user != 'denied';

  @override
  Future<bool> canView(Jwt? jwt, _Member row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, _Member before, _Member after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, _Member row) async => true;
}

final class _OrgExtensions extends Extension<_Org> {
  _OrgExtensions() : super(_orgs);

  @override
  Future<void> beforeUpdate(_Org object, Jwt? jwt) async {
    _hookCalls.add('before update orgs ${object.id}');
  }

  @override
  Future<void> afterUpdateSuccess(_Org before, _Org after, Jwt? jwt) async {
    _hookCalls.add('after update orgs ${after.id}');
  }
}

final class _MemberExtensions extends Extension<_Member> {
  _MemberExtensions() : super(_members);

  @override
  Future<void> beforeCreate(_Member object, Jwt? jwt) async {
    if (object.user == 'refuse') {
      throw const HttpError.forbidden(
        code: 'member_refused',
        message: 'That member is not allowed',
      );
    }
    _hookCalls.add('before create members ${object.id}');
  }

  @override
  Future<void> afterCreateSuccess(_Member row, Jwt? jwt) async {
    _hookCalls.add('after create members ${row.id}');
  }

  @override
  Future<void> beforeUpdate(_Member object, Jwt? jwt) async {
    _hookCalls.add('before update members ${object.id}');
  }

  @override
  Future<void> afterUpdateSuccess(
    _Member before,
    _Member after,
    Jwt? jwt,
  ) async {
    _hookCalls.add('after update members ${after.id}');
  }

  @override
  Future<void> beforeDelete(_Member object, Jwt? jwt) async {
    _hookCalls.add('before delete members ${object.id}');
  }

  @override
  Future<void> afterDeleteSuccess(_Member row, Jwt? jwt) async {
    _hookCalls.add('after delete members ${row.id}');
  }
}
