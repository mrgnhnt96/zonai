import 'package:test/test.dart';
import 'package:zonai_schema/src/payloads/maintenance_actions.dart';

/// [SpaceReclamationResult] crosses the wire between the server and a browser
/// that cannot share its Dart types, so every field has to survive the trip.
///
/// The fields worth being pedantic about are [SpaceReclamationResult.target],
/// which is what keeps a result on screen from being read as being about a
/// different database, and [SpaceReclamationResult.skipped], whose `null` and
/// non-`null` forms are the distinction the type exists to carry.
void main() {
  group('SpaceReclamationResult', () {
    test('round-trips a blocked attempt, reason intact', () {
      const original = SpaceReclamationResult(
        target: 'main',
        reclaimableBytes: 9_961_472,
        reclaimedBytes: 0,
        vacuumed: false,
        skipped: 'not enough free space on the volume to rewrite the file',
      );

      final restored = SpaceReclamationResult.fromJson(original.toJson());

      expect(restored.target, 'main');
      expect(restored.reclaimableBytes, 9_961_472);
      expect(restored.reclaimedBytes, 0);
      expect(restored.vacuumed, isFalse);
      // Verbatim, not "was there a reason": a full volume reclaims nothing,
      // and without the string that is indistinguishable from having had
      // nothing to reclaim.
      expect(
        restored.skipped,
        'not enough free space on the volume to rewrite the file',
      );
    });

    test('round-trips a successful reclaim, with skipped null', () {
      const original = SpaceReclamationResult(
        target: 'logdb',
        reclaimableBytes: 4_096_000,
        reclaimedBytes: 4_091_904,
        vacuumed: true,
      );

      final restored = SpaceReclamationResult.fromJson(original.toJson());

      expect(restored.target, 'logdb');
      expect(restored.reclaimedBytes, 4_091_904);
      expect(restored.vacuumed, isTrue);
      expect(restored.skipped, isNull);
    });

    test('uses snake_case keys on the wire', () {
      const result = SpaceReclamationResult(
        target: 'ratedb',
        reclaimableBytes: 1,
        reclaimedBytes: 2,
        vacuumed: true,
        skipped: null,
      );

      expect(result.toJson(), {
        'target': 'ratedb',
        'reclaimable_bytes': 1,
        'reclaimed_bytes': 2,
        'vacuumed': true,
        'skipped': null,
      });
    });

    test('skipped is emitted as an explicit null rather than omitted', () {
      // An absent key and a null one decode the same here, but the dashboard
      // is not the only reader of this JSON -- an operator reading the raw
      // response should see the field and its emptiness, not have to know
      // that a missing key means "not blocked".
      const result = SpaceReclamationResult(
        target: 'main',
        reclaimableBytes: 0,
        reclaimedBytes: 0,
        vacuumed: false,
      );

      expect(result.toJson(), contains('skipped'));
      expect(result.toJson()['skipped'], isNull);
    });

    test('a target that is not a reclaimable schema still decodes', () {
      // fromJson is a decoder, not a validator: the allowlist is enforced
      // where the request is handled, and a result that quietly refused to
      // parse would turn a server-side bug into a blank card.
      final restored = SpaceReclamationResult.fromJson(const {
        'target': 'nonsense',
        'reclaimable_bytes': 0,
        'reclaimed_bytes': 0,
        'vacuumed': false,
        'skipped': null,
      });

      expect(restored.target, 'nonsense');
    });

    test('every reclaimable schema is expressible as a target', () {
      for (final schema in kReclaimableSchemas) {
        final restored = SpaceReclamationResult.fromJson(
          SpaceReclamationResult(
            target: schema,
            reclaimableBytes: 0,
            reclaimedBytes: 0,
            vacuumed: false,
          ).toJson(),
        );
        expect(restored.target, schema);
      }
    });
  });

  group('LogSpaceReclamationResult', () {
    test('is unchanged and still round-trips', () {
      // The legacy log-only route declares this as its return type and
      // zonai_client's generated data source decodes it. Generalising the
      // card must not disturb it, so this pins that it still works.
      const original = LogSpaceReclamationResult(
        reclaimableBytes: 512,
        reclaimedBytes: 256,
        vacuumed: true,
        skipped: null,
      );

      final restored = LogSpaceReclamationResult.fromJson(original.toJson());

      expect(restored.reclaimableBytes, 512);
      expect(restored.reclaimedBytes, 256);
      expect(restored.vacuumed, isTrue);
      expect(restored.skipped, isNull);
      // No `target` key: this type is about the log database by definition,
      // and adding one would change a shape other packages already decode.
      expect(original.toJson().keys, isNot(contains('target')));
    });
  });
}
