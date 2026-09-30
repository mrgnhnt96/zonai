import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_sync/zonai_sync.dart';

void main() {
  group('ZonaiSyncRemote.classify', () {
    SyncRemoteException c(int status, [String? body]) =>
        ZonaiSyncRemote.classify(status, body: body);

    test('maps statuses to what the engine should do', () {
      expect(c(401).kind, FailureKind.unauthorized);
      expect(c(403).kind, FailureKind.forbidden);
      expect(c(404).kind, FailureKind.notFound);
      expect(c(409).kind, FailureKind.exists);
      expect(c(400).kind, FailureKind.invalid);
      expect(c(422).kind, FailureKind.invalid);
      expect(c(503).kind, FailureKind.server);
    });

    test('429 carries retryAfter from the body', () {
      final e = c(429, '{"error":"Rate limit exceeded","retryAfter":25}');
      expect(e.kind, FailureKind.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 25));
    });

    test('412 carries the current row from the precondition body', () {
      final e = c(
        412,
        '{"error":{"code":"precondition_failed","details":{"current":'
        '[{"id":"n1","rev":4,"updated_at":"2026-09-29T12:00:00.000Z"}]}}}',
      );
      expect(e.kind, FailureKind.revisionConflict);
      expect(e.current?.rev, 4);
      expect(
        e.current?.updatedAt,
        DateTime.utc(2026, 9, 29, 12).millisecondsSinceEpoch,
      );
    });

    test('an unreadable body never throws', () {
      expect(c(412, 'not json').current, isNull);
      expect(c(429, '[]').retryAfter, isNull);
    });
  });

  test('a 409 on UPDATE is a constraint violation, not "exists"', () {
    // Review finding #6: "exists" makes sense for a create; on an update a
    // 409 is a unique-constraint violation that no retry will fix.
    final e = ZonaiSyncRemote.forUpdate(
      const SyncRemoteException(FailureKind.exists, message: 'UNIQUE failed'),
    );
    expect(e.kind, FailureKind.invalid);
    expect(e.message, contains('UNIQUE failed'));
  });

  test('server revision can be switched on per table', () {
    // #51 lands $.revision per table; a table on it refuses a client rev
    // with 400, so the flag cannot be all-or-nothing.
    const caps = ZonaiSyncCapabilities(serverRevisionTables: {'notes'});
    expect(caps.serverOwnsRevision('notes'), isTrue);
    expect(caps.serverOwnsRevision('tags'), isFalse);
    const all = ZonaiSyncCapabilities(serverRevision: true);
    expect(all.serverOwnsRevision('tags'), isTrue);
  });

  test('the library never imports dart:io, so it builds for the web', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            RegExp(
              r"""(import|export)\s+['"]dart:io['"]""",
            ).hasMatch(f.readAsStringSync()))
          f.path,
    ];
    final scanned = Directory(
      'lib',
    ).listSync(recursive: true).where((f) => f.path.endsWith('.dart')).length;
    expect(scanned, greaterThan(5), reason: 'the scan saw the library');
    expect(offenders, isEmpty);
  });
}
