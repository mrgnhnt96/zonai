import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';

/// The `_cleanup_logs` -> host round trip, as JSON.
///
/// Every cron message crosses a process boundary and is reassembled by a
/// `switch` on its `path` string. Nothing type-checks that: a path that does
/// not match any case throws `Invalid cron request path` at runtime, on the
/// nightly job, in production. These are the cheapest possible check that the
/// two halves agree.
void main() {
  test('the request survives a round trip through JSON', () {
    final sent = ReclaimLogSpaceRequest();
    final received = CronRequest.fromJson(sent.toJson());

    expect(received, isA<ReclaimLogSpaceRequest>());
    expect(received.id, sent.id);
  });

  test('the response survives a round trip, including a null skip reason', () {
    final sent = ReclaimLogSpaceResponse(
      id: 'abc',
      reclaimableBytes: 41943040,
      reclaimedBytes: 39845888,
      vacuumed: true,
      skipped: null,
    );

    final received = CronResponse.fromJson(sent.toJson());

    expect(received, isA<ReclaimLogSpaceResponse>());
    final result = received as ReclaimLogSpaceResponse;
    expect(result.id, 'abc');
    expect(result.reclaimableBytes, 41943040);
    expect(result.reclaimedBytes, 39845888);
    expect(result.vacuumed, isTrue);
    expect(
      result.skipped,
      isNull,
      reason:
          'a null reason is omitted from the payload rather than sent as '
          'null, so the decoding side has to tolerate the key being absent -- '
          'and this is the common case, not the edge one',
    );
  });

  test('a refusal carries its reason across', () {
    // The case a human is meant to act on: the volume has no room for the
    // rewrite. The operator-facing sentence is emitted host-side, but the
    // cron still reports that it did not happen.
    final sent = ReclaimLogSpaceResponse(
      id: 'abc',
      reclaimableBytes: 41943040,
      reclaimedBytes: 0,
      vacuumed: false,
      skipped: 'not enough free disk for the rewrite',
    );

    final received =
        CronResponse.fromJson(sent.toJson()) as ReclaimLogSpaceResponse;

    expect(received.vacuumed, isFalse);
    expect(received.skipped, 'not enough free disk for the rewrite');
    expect(received.reclaimedBytes, 0);
  });
}
