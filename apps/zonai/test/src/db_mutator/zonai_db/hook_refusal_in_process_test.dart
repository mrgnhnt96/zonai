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
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger, Table;
import 'package:zonai_schema/zonai_schema.dart' as schema show Table;

import '../../../support/temp_directory.dart';

/// Hook refusals with the extensions in-process, the way `zonai dev` and
/// project-linked binaries run them (`HostWorkerRegistries`).
///
/// The worker path is covered over HTTP by `hook_refusal_http_e2e_test.dart`.
/// This file holds the in-process path to the same answers: only a `before*`
/// hook's 4xx on the request's own write is a refusal, and everything else,
/// a 5xx `HttpError`, an after-hook's `HttpError` or a refused queued write,
/// fails as an ordinary error, which the server answers 500.
void main() {
  late io.Directory projectRoot;
  late Settings settings;

  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }

    projectRoot = createCanonicalTempSync('zonai_hook_refusal_');
    // ZonaiDb.open() refuses a project with no migrations directory. The app
    // table below is created by hand, so an empty one is all it needs.
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
    HostWorkerRegistries.operations = DbOperations(
      operations: [_PostOperations()],
      tables: [_posts],
    );
    HostWorkerRegistries.rules = DbRules(
      rules: [_PostTableRules(), _PostRowRules()],
    );
    HostWorkerRegistries.extensions = DbExtensions(
      extensions: [_PostExtensions()],
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
          await sql.execute('DROP TABLE IF EXISTS "posts"');
          await sql.execute(
            'CREATE TABLE "posts" ("id" TEXT PRIMARY KEY, '
            '"title" TEXT NOT NULL)',
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

  Future<List<String>> titles(ZonaiDb db) async {
    final sql = await db.open();
    final result = await sql.execute(
      'SELECT "title" FROM "posts" ORDER BY "title"',
    );
    return [for (final row in result.rows) row[0]! as String];
  }

  Future<Object?> create(ZonaiDb db, String title) async {
    try {
      await db.create('posts', CreatePayload(object: {'title': title}));
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  test('a before-hook 4xx is the refusal, and nothing is written', () async {
    await run((db) async {
      final failure = await create(db, 'refuse');

      expect(
        failure,
        isA<HookRefusedException>()
            .having((e) => e.error.statusCode, 'statusCode', 403)
            .having((e) => e.error.code, 'code', 'post_refused'),
      );
      expect(await titles(db), isEmpty);
    });
  });

  test('a before-hook 5xx HttpError is an ordinary failure', () async {
    await run((db) async {
      final failure = await create(db, 'refuse-500');

      expect(failure, isNot(isA<HookRefusedException>()));
      expect(failure, isNot(isA<HttpError>()));
      expect(failure, isNotNull);
    });
  });

  test('an after-hook HttpError is an ordinary failure, after the write was '
      'saved', () async {
    await run((db) async {
      final failure = await create(db, 'after-refuse');

      expect(failure, isNot(isA<HookRefusedException>()));
      expect(failure, isNot(isA<HttpError>()));
      expect(failure, isNotNull);
      expect(await titles(db), ['after-refuse']);
    });
  });

  test('a queued write its before-hook refuses is an ordinary failure, and the '
      "request's own write stays", () async {
    await run((db) async {
      final failure = await create(db, 'queue-refused');

      expect(failure, isA<StateError>());
      expect('$failure', contains('queued by a hook was refused'));
      expect(await titles(db), ['queue-refused']);
    });
  });

  test('a title no hook minds is written', () async {
    await run((db) async {
      expect(await create(db, 'fine'), isNull);
      expect(await titles(db), ['fine']);
    });
  });
}

const _config = AppConfig(
  appName: 'hook-refusal-fixture',
  passwordSecret: 'test-password-secret',
  jwtSecret: 'test-jwt-secret',
);

final class _PostId implements Id {
  const _PostId(this.value);

  static _PostId generate() => _PostId(Id.generate('pst'));

  @override
  final String value;

  @override
  String toString() => value;
}

final class _Post {
  _Post({required this.id, required this.title});

  final _PostId id;
  final String title;
}

final class _PostTable extends schema.Table<_Post> {
  _PostTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _PostId.new,
        generate: _PostId.generate,
      ),
      title = $.text('title', (s) => s.title);

  @override
  _Post fromRow(RowReader read) => _Post(id: read(id), title: read(title));

  final IdColumn<_PostId> id;
  final TextColumn title;
}

final _posts = table('posts', _PostTable.new);

final class _PostOperations extends TableOperations<_PostTable, _Post> {
  _PostOperations() : super(_posts);
}

final class _PostTableRules extends TableRules<_PostTable, _Post> {
  _PostTableRules() : super(_posts);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}

final class _PostRowRules extends RowRules<_PostTable, _Post> {
  _PostRowRules() : super(_posts);

  @override
  Future<bool> canCreate(Jwt? jwt, _Post row) async => true;
}

final class _PostExtensions extends Extension<_Post> {
  _PostExtensions() : super(_posts);

  @override
  Future<void> beforeCreate(_Post object, Jwt? jwt) async {
    switch (object.title) {
      case 'refuse':
        throw const HttpError.forbidden(
          code: 'post_refused',
          message: 'That title is not allowed',
        );
      case 'refuse-500':
        throw const HttpError.internal(code: 'hook_5xx', message: 'Not 4xx');
    }
  }

  @override
  Future<void> afterCreateSuccess(_Post row, Jwt? jwt) async {
    switch (row.title) {
      case 'after-refuse':
        throw const HttpError.forbidden(code: 'too_late', message: 'Saved');
      case 'queue-refused':
        // What `mutate.create` amounts to once it reaches the host. In
        // process the worker-side `mutate` is not bound, so the write goes
        // where Mailman puts the ones a worker's reply carries (as
        // `push_fanout_test.dart` does).
        mutations.addAll([
          CreateRecordRequest(
            table: 'posts',
            objects: [
              {'title': 'refuse'},
            ],
            parent: CreateExtensionRequest.afterSuccess(
              table: 'posts',
              object: {'title': row.title},
              jwt: jwt,
            ),
            jwt: jwt,
          ),
        ]);
    }
  }
}
