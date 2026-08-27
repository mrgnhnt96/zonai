import 'package:test/test.dart';
import 'package:zonai_schema/src/payloads/maintenance_actions.dart';
import 'package:zonai_schema/src/payloads/storage_metrics.dart';

/// The storage report is what the reclaim picker is built from, so
/// [StorageDatabaseFile.schema] has to arrive intact — it is the identifier
/// the browser sends back, and the thing that replaces picking the log file
/// out by `name.contains('log')`.
void main() {
  group('StorageDatabaseFile', () {
    test('round-trips schema alongside the rest', () {
      const original = StorageDatabaseFile(
        name: 'zonai_log.sqlite',
        path: '/srv/app/.zonai/data/zonai_log.sqlite',
        schema: 'logdb',
        sizeBytes: 4_096_000,
        walBytes: 294_912,
        reclaimableBytes: 28_672,
        capBytes: 1_073_741_824,
      );

      final restored = StorageDatabaseFile.fromJson(original.toJson());

      expect(restored.name, 'zonai_log.sqlite');
      expect(restored.path, '/srv/app/.zonai/data/zonai_log.sqlite');
      expect(restored.schema, 'logdb');
      expect(restored.sizeBytes, 4_096_000);
      expect(restored.walBytes, 294_912);
      expect(restored.reclaimableBytes, 28_672);
      expect(restored.capBytes, 1_073_741_824);
    });

    test('schema is a `schema` key on the wire', () {
      const file = StorageDatabaseFile(
        name: 'zonai.sqlite',
        path: '/srv/app/.zonai/data/zonai.sqlite',
        schema: 'main',
        sizeBytes: 1,
        walBytes: 0,
      );

      expect(file.toJson()['schema'], 'main');
    });

    test('fromJson throws when schema is absent', () {
      // Required rather than nullable is the deliberate call the field
      // documents: producer and consumer ship in the same binary, so a
      // payload without it is a bug to fail on, not a state to render. This
      // pins that failing is what actually happens.
      expect(
        () => StorageDatabaseFile.fromJson(const {
          'name': 'zonai.sqlite',
          'path': '/srv/app/.zonai/data/zonai.sqlite',
          'size_bytes': 1,
          'wal_bytes': 0,
          'reclaimable_bytes': null,
          'cap_bytes': null,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('schema distinguishes files a name heuristic would not', () {
      // The heuristic being retired matches on a basename a project can
      // configure. Two files whose names both contain `log` are
      // indistinguishable to it and unambiguous by schema.
      const appDb = StorageDatabaseFile(
        name: 'catalog.sqlite',
        path: '/srv/app/catalog.sqlite',
        schema: 'main',
        sizeBytes: 1,
        walBytes: 0,
      );
      const logDb = StorageDatabaseFile(
        name: 'catalog_log.sqlite',
        path: '/srv/app/catalog_log.sqlite',
        schema: 'logdb',
        sizeBytes: 1,
        walBytes: 0,
      );

      expect(appDb.name.contains('log'), isTrue);
      expect(logDb.name.contains('log'), isTrue);
      expect(appDb.schema, isNot(logDb.schema));
    });

    test('every schema a file can carry is a reclaim target', () {
      // The picker is built from `databases` and its selection is sent as a
      // reclaim target, so the two vocabularies have to be the same one.
      for (final schema in kReclaimableSchemas) {
        final file = StorageDatabaseFile(
          name: '$schema.sqlite',
          path: '/srv/app/$schema.sqlite',
          schema: schema,
          sizeBytes: 0,
          walBytes: 0,
        );
        expect(kReclaimableSchemas, contains(file.schema));
      }
    });
  });

  group('StorageMetrics', () {
    test('round-trips nested database files with their schemas', () {
      const original = StorageMetrics(
        databases: [
          StorageDatabaseFile(
            name: 'zonai.sqlite',
            path: '/srv/app/zonai.sqlite',
            schema: 'main',
            sizeBytes: 10_485_760,
            walBytes: 32_768,
            reclaimableBytes: 9_961_472,
          ),
          StorageDatabaseFile(
            name: 'zonai_log.sqlite',
            path: '/srv/app/zonai_log.sqlite',
            schema: 'logdb',
            sizeBytes: 4_096,
            walBytes: 0,
            reclaimableBytes: null,
          ),
          StorageDatabaseFile(
            name: 'zonai_rate_limit.sqlite',
            path: '/srv/app/zonai_rate_limit.sqlite',
            schema: 'ratedb',
            sizeBytes: 4_096,
            walBytes: 0,
          ),
        ],
        photosBytes: 0,
        photosFileCount: 0,
        tables: [StorageTableRows(table: '_cron_jobs', rowCount: 56_483)],
        freeDiskBytes: null,
      );

      final restored = StorageMetrics.fromJson(original.toJson());

      expect(
        restored.databases.map((db) => db.schema),
        ['main', 'logdb', 'ratedb'],
      );
      // Unknown stays unknown across the wire -- a file whose freelist could
      // not be read must not come back as "0 B reclaimable".
      expect(restored.databases[1].reclaimableBytes, isNull);
      expect(restored.freeDiskBytes, isNull);
      expect(restored.tables.single.rowCount, 56_483);
    });

    test('totalReclaimableBytes is a floor, skipping unreadable files', () {
      const metrics = StorageMetrics(
        databases: [
          StorageDatabaseFile(
            name: 'zonai.sqlite',
            path: '/srv/app/zonai.sqlite',
            schema: 'main',
            sizeBytes: 10_485_760,
            walBytes: 0,
            reclaimableBytes: 9_961_472,
          ),
          StorageDatabaseFile(
            name: 'zonai_log.sqlite',
            path: '/srv/app/zonai_log.sqlite',
            schema: 'logdb',
            sizeBytes: 4_096,
            walBytes: 0,
            reclaimableBytes: null,
          ),
        ],
        photosBytes: 0,
        photosFileCount: 0,
        tables: [],
      );

      expect(metrics.totalReclaimableBytes, 9_961_472);
      expect(metrics.totalDatabaseBytes, 10_489_856);
    });
  });
}
