import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger, Table;
import 'package:zonai_schema/zonai_schema.dart' as schema show Table;

import '../../../support/fake_s3_server.dart';
import '../../../support/temp_directory.dart';

/// What `ZonaiDb.viewPhoto` tells the server to cache by, against real photo
/// rows and files with the rules in-process.
///
/// The ETag has to move when `PATCH /img/:id` replaces the bytes, or a cache
/// revalidating the same URL is told its stale copy is current. And
/// `publiclyViewable` has to follow the rules as a caller with no JWT would
/// meet them, whoever is actually asking, or the response says `public` for
/// a photo a shared cache must not store.
void main() {
  late io.Directory projectRoot;
  late Settings settings;

  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }

    projectRoot = createCanonicalTempSync('zonai_photo_view_');
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

  /// Registers photo rules that let anyone create and replace photos, let a
  /// signed-in caller view them, and let a caller with no JWT view them only
  /// where [anonymousTable] and [anonymousRow] say so.
  void rules({required bool anonymousTable, required bool anonymousRow}) {
    HostWorkerRegistries.operations = DbOperations(
      operations: [_PostOperations()],
      tables: [_posts],
    );
    HostWorkerRegistries.rules = DbRules(
      rules: [
        _PhotoTableRules(anonymousView: anonymousTable),
        _PhotoRowRules(anonymousView: anonymousRow),
      ],
    );
    HostWorkerRegistries.extensions = DbExtensions(extensions: []);
  }

  Future<void> run(
    Future<void> Function(ZonaiDb db) body, {
    AppConfig config = _config,
    Map<String, String>? environment,
  }) async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }
    // Built inside the scope, which its constructor reads settings from.
    late final ZonaiDb db;
    await runMergedScopedFuture(
      () async {
        db = _SignedInZonaiDb(config: config, environment: environment);
        try {
          await db.open();
          await body(db);
        } finally {
          await db.dispose();
        }
      },
      override: {
        fsProvider.overrideWith(LocalFileSystem.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        settingsProvider.overrideWith(() => settings),
        // `_getPhoto` parses the token through the provider, which is how
        // the stand-in signed-in caller below reaches it.
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
        processProvider,
        cleanUpProvider,
        executableStopProvider,
        migrateProvider,
      },
    );
  }

  Future<String> upload(ZonaiDb db, List<int> bytes) async {
    final created = await db.createPhoto(
      token: null,
      meta: const PhotoCreateMeta(table: 'posts'),
      contentType: 'image/png',
      image: Stream.value(bytes),
    );
    return created['id']! as String;
  }

  test('the ETag changes when PATCH replaces the bytes', () async {
    rules(anonymousTable: true, anonymousRow: true);
    await run((db) async {
      final id = await upload(db, _png(4));
      final before = await db.viewPhoto(id, token: null);

      // A second ETag read with nothing changed is the control: the tag is
      // stable, so a cache that revalidates gets its 304.
      expect((await db.viewPhoto(id, token: null)).etag, before.etag);

      await db.updatePhoto(token: null, id: id, image: Stream.value(_png(9)));
      final after = await db.viewPhoto(id, token: null);

      expect(after.extension, before.extension, reason: 'same id, same URL');
      expect(after.etag, isNot(before.etag));
      expect(await after.openRead().expand((chunk) => chunk).toList(), _png(9));
    });
  });

  test('with S3 storage, photos live in the bucket and PATCH moves the '
      'ETag', () async {
    final bucket = await FakeS3Server.start();
    addTearDown(bucket.close);
    rules(anonymousTable: true, anonymousRow: true);

    await run(
      config: AppConfig(
        appName: _config.appName,
        passwordSecret: _config.passwordSecret,
        jwtSecret: _config.jwtSecret,
        photos: PhotosConfig(
          storage: S3PhotoStorage(
            endpoint: bucket.endpoint.toString(),
            bucket: bucket.bucket,
          ),
        ),
      ),
      environment: {
        S3PhotoStorage.accessKeyIdVariable:
            FakeS3Server.credentials.accessKeyId,
        S3PhotoStorage.secretAccessKeyVariable:
            FakeS3Server.credentials.secretAccessKey,
      },
      (db) async {
        final id = await upload(db, _png(4));
        expect(bucket.objects, hasLength(1));
        final before = await db.viewPhoto(id, token: null);
        expect(
          await before.openRead().expand((chunk) => chunk).toList(),
          _png(4),
        );

        // Same size and, likely, the same second: only the bucket's content
        // ETag can tell these apart.
        await db.updatePhoto(token: null, id: id, image: Stream.value(_png(5)));
        final after = await db.viewPhoto(id, token: null);

        expect(after.etag, isNot(before.etag));
        expect(
          await after.openRead().expand((chunk) => chunk).toList(),
          _png(5),
        );
        expect(bucket.objects, hasLength(1), reason: 'the old object is gone');
      },
    );
  });

  group('redirect', () {
    late FakeS3Server bucket;

    setUp(() async {
      bucket = await FakeS3Server.start();
      addTearDown(bucket.close);
    });

    Future<void> runOnBucket(
      Future<void> Function(ZonaiDb db) body, {
      bool redirect = true,
      String? publicBaseUrl = 'https://img.example.com/',
    }) => run(
      config: AppConfig(
        appName: _config.appName,
        passwordSecret: _config.passwordSecret,
        jwtSecret: _config.jwtSecret,
        photos: PhotosConfig(
          storage: S3PhotoStorage(
            endpoint: bucket.endpoint.toString(),
            bucket: bucket.bucket,
            publicBaseUrl: publicBaseUrl,
            redirect: redirect,
            presignedUrlSeconds: 60,
          ),
        ),
      ),
      environment: {
        S3PhotoStorage.accessKeyIdVariable:
            FakeS3Server.credentials.accessKeyId,
        S3PhotoStorage.secretAccessKeyVariable:
            FakeS3Server.credentials.secretAccessKey,
      },
      body,
    );

    Future<List<int>> fetch(Uri url) async {
      final response = await http.get(url);
      expect(response.statusCode, 200, reason: response.body);
      return response.bodyBytes;
    }

    test('is off unless the config asks for it', () async {
      rules(anonymousTable: true, anonymousRow: true);
      await runOnBucket(redirect: false, (db) async {
        final id = await upload(db, _png(4));

        expect((await db.viewPhoto(id, token: null)).redirect, isNull);
      });
    });

    test(
      'sends a public photo to publicBaseUrl, versioned by its ETag',
      () async {
        rules(anonymousTable: true, anonymousRow: true);
        await runOnBucket((db) async {
          final id = await upload(db, _png(4));
          final view = await db.viewPhoto(id, token: _signedIn);

          final redirect = view.redirect!;
          expect(redirect.presigned, isFalse);
          expect(
            redirect.location.toString(),
            'https://img.example.com/posts/$id.png'
            '?v=${view.etag.replaceAll('"', '')}',
          );

          // The same key after PATCH, so only the version tells a CDN in
          // front of the public URL that its copy is stale.
          await db.updatePhoto(
            token: null,
            id: id,
            image: Stream.value(_png(5)),
          );
          final after = (await db.viewPhoto(id, token: null)).redirect!;
          expect(after.location.path, redirect.location.path);
          expect(after.location, isNot(redirect.location));
        });
      },
    );

    test(
      'presigns a photo the rules restrict, and the URL serves it',
      () async {
        rules(anonymousTable: true, anonymousRow: false);
        await runOnBucket((db) async {
          final id = await upload(db, _png(4));

          final redirect = (await db.viewPhoto(id, token: _signedIn)).redirect!;

          expect(redirect.presigned, isTrue);
          expect(redirect.location.host, bucket.endpoint.host);
          expect(redirect.location.queryParameters['X-Amz-Expires'], '60');
          expect(await fetch(redirect.location), _png(4));
        });
      },
    );

    test('presigns a public photo when there is no publicBaseUrl', () async {
      rules(anonymousTable: true, anonymousRow: true);
      await runOnBucket(publicBaseUrl: null, (db) async {
        final id = await upload(db, _png(4));

        final redirect = (await db.viewPhoto(id, token: null)).redirect!;

        expect(redirect.presigned, isTrue);
        expect(await fetch(redirect.location), _png(4));
      });
    });

    test(
      'a presigned URL stops working when the signature is altered',
      () async {
        rules(anonymousTable: true, anonymousRow: false);
        await runOnBucket((db) async {
          final id = await upload(db, _png(4));
          final location = (await db.viewPhoto(
            id,
            token: _signedIn,
          )).redirect!.location;

          // Pointing a valid signature at another key is the forgery the
          // signature exists to stop.
          final forged = Uri.parse(
            location.toString().replaceFirst('/posts/', '/other/'),
          );
          expect((await http.get(forged)).statusCode, 403);
        });
      },
    );

    for (final (name, anonymousTable, anonymousRow) in [
      ('table', false, true),
      ('row', true, false),
    ]) {
      test('is never handed out when the $name rule refuses', () async {
        rules(anonymousTable: anonymousTable, anonymousRow: anonymousRow);
        await runOnBucket((db) async {
          final id = await upload(db, _png(4));

          await expectLater(
            db.viewPhoto(id, token: null),
            throwsA(isA<PermissionException>()),
          );
        });
      });
    }
  });

  group('publiclyViewable', () {
    test('is true when the rules let a caller with no JWT view it', () async {
      rules(anonymousTable: true, anonymousRow: true);
      await run((db) async {
        final id = await upload(db, _png(4));

        expect((await db.viewPhoto(id, token: null)).publiclyViewable, isTrue);
        expect(
          (await db.viewPhoto(id, token: _signedIn)).publiclyViewable,
          isTrue,
        );
      });
    });

    test(
      'is false for a signed-in viewer when the row rule needs a JWT',
      () async {
        rules(anonymousTable: true, anonymousRow: false);
        await run((db) async {
          final id = await upload(db, _png(4));

          final view = await db.viewPhoto(id, token: _signedIn);

          expect(view.publiclyViewable, isFalse);
        });
      },
    );

    test(
      'is false for a signed-in viewer when the table rule needs a JWT',
      () async {
        rules(anonymousTable: false, anonymousRow: true);
        await run((db) async {
          final id = await upload(db, _png(4));

          final view = await db.viewPhoto(id, token: _signedIn);

          expect(view.publiclyViewable, isFalse);
        });
      },
    );
  });
}

const _signedIn = 'signed-in';

/// A PNG signature followed by [length] bytes of filler: enough for the
/// upload's magic-byte check, and a different [length] is a different file.
List<int> _png(int length) => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  for (var i = 0; i < length; i++) i,
];

const _config = AppConfig(
  appName: 'photo-view-fixture',
  passwordSecret: 'test-password-secret',
  jwtSecret: 'test-jwt-secret',
);

/// A [ZonaiDb] that reads the token [_signedIn] as a signed-in user, so a
/// view can be asked for with a JWT without an auth table and a sign-in.
class _SignedInZonaiDb extends ZonaiDb {
  _SignedInZonaiDb({
    required AppConfig config,
    Map<String, String>? environment,
  }) : super(
         configResolver: ConfigResolver.fixed(config),
         environment: environment,
       );

  @override
  Future<Jwt?> parseJwt(String? token, {bool allowApiToken = false}) async {
    if (token != _signedIn) return null;
    return Jwt(
      userId: UnknownId('usr_viewer'),
      table: 'users',
      jwtId: JwtId('jwt_viewer'),
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: const {},
      claims: const {},
      admin: (isAdmin: false, canEdit: null),
    );
  }
}

final class _PhotoTableRules extends TableRules<PhotosTable, PhotoEntry> {
  _PhotoTableRules({required this.anonymousView}) : super(photos);

  final bool anonymousView;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => jwt != null || anonymousView;
}

final class _PhotoRowRules extends RowRules<PhotosTable, PhotoEntry> {
  _PhotoRowRules({required this.anonymousView}) : super(photos);

  final bool anonymousView;

  @override
  Future<bool> canCreate(Jwt? jwt, PhotoEntry row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, PhotoEntry before, PhotoEntry after) async =>
      true;

  @override
  Future<bool> canView(Jwt? jwt, PhotoEntry row) async =>
      jwt != null || anonymousView;
}

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
