import 'package:test/test.dart';
import 'package:zonai_web/utils/api_tokens.dart';

/// The pure half of the API Tokens screen (`docs/api-tokens-design.md` §8):
/// what the list says about a row, and what the form sends.
///
/// Worth its own file because both halves are answers a screenshot cannot
/// check. A row labelled "Live" that is actually revoked, and a draft that
/// quietly sends `admin: false`, both look completely correct.
final _now = DateTime.utc(2026, 8, 24, 12);

ApiTokenRow _row({
  String id = 'abc123_pat',
  String name = 'nightly-backup',
  DateTime? createdAt,
  DateTime? expiresAt,
  DateTime? revokedAt,
  DateTime? lastUsedAt,
  ApiTokenScopeView scope = const ApiTokenScopeView(
    tables: ['orders'],
    operations: ['view', 'list'],
    customOperations: [],
    admin: true,
    canEdit: false,
  ),
}) {
  return ApiTokenRow(
    id: id,
    name: name,
    tokenPrefix: 'zonai_pat_qT501Hoh',
    scope: scope,
    createdAt: createdAt ?? _now.subtract(const Duration(days: 3)),
    expiresAt: expiresAt,
    revokedAt: revokedAt,
    lastUsedAt: lastUsedAt,
  );
}

void main() {
  group('status', () {
    test('a live token is live', () {
      expect(_row().statusAt(_now), ApiTokenStatus.live);
      expect(_row(expiresAt: _now.add(const Duration(days: 1))).statusAt(_now), ApiTokenStatus.live);
    });

    test('no expiry never expires, however old the row is', () {
      // The whole point of the feature, and the reading a null-as-epoch bug
      // would invert: "expires never" and "expired in 1970" are opposite
      // answers, and the second one greys out a working credential.
      expect(_row(createdAt: DateTime.utc(1990)).statusAt(_now), ApiTokenStatus.live);
      expect(_row().isExpiredAt(_now), isFalse);
    });

    test('a past expiry is expired', () {
      expect(_row(expiresAt: _now.subtract(const Duration(days: 1))).statusAt(_now), ApiTokenStatus.expired);
    });

    test('revoked beats expired', () {
      // A token somebody withdrew is withdrawn whether or not its expiry has
      // also passed. Reading it the other way credits the clock for a decision
      // a person made, and sends whoever is debugging it to the wrong place.
      final row = _row(
        expiresAt: _now.subtract(const Duration(days: 2)),
        revokedAt: _now.subtract(const Duration(days: 1)),
      );

      expect(row.statusAt(_now), ApiTokenStatus.revoked);
    });

    test('revoking is refused only for a token already revoked', () {
      expect(revokeRefusal(_row()), isNull);
      expect(revokeRefusal(_row(expiresAt: _now.subtract(const Duration(days: 1)))), isNull);
      expect(revokeRefusal(_row(revokedAt: _now)), contains('Already revoked'));
    });
  });

  group('the timeline line', () {
    test('says when a token has never been used', () {
      // The token nobody has ever presented is the one it is safe to delete,
      // and that is the question this screen gets opened to answer.
      expect(describeTokenTimeline(_row(), now: _now), contains('never used'));
    });

    test('says never expires rather than leaving it blank', () {
      expect(describeTokenTimeline(_row(), now: _now), contains('never expires'));
    });

    test('distinguishes an upcoming expiry from a past one', () {
      expect(
        describeTokenTimeline(_row(expiresAt: _now.add(const Duration(days: 60))), now: _now),
        contains('expires in 2mo'),
      );
      expect(
        describeTokenTimeline(_row(expiresAt: _now.subtract(const Duration(days: 2))), now: _now),
        contains('expired 2d ago'),
      );
    });

    test('reports the revocation instead of the expiry', () {
      final line = describeTokenTimeline(
        _row(expiresAt: _now.add(const Duration(days: 60)), revokedAt: _now.subtract(const Duration(hours: 3))),
        now: _now,
      );

      expect(line, contains('revoked 3h ago'));
      expect(line, isNot(contains('expires')));
    });
  });

  group('describeScope', () {
    test('spells the wildcard out', () {
      // A bare asterisk in a list is the credential with the most reach, shown
      // as the smallest glyph on the page.
      final line = describeScope(
        const ApiTokenScopeView(tables: ['*'], operations: ['list'], customOperations: [], admin: true, canEdit: false),
      );

      expect(line, contains('every collection'));
      expect(line, isNot(contains('*')));
    });

    test('names the collections and operations otherwise', () {
      expect(describeScope(_row().scope), 'orders · view, list');
    });

    test('says so when a scope reaches nothing', () {
      expect(describeScope(ApiTokenScopeView.empty), 'no collections · nothing');
    });
  });

  group('parseApiTokens', () {
    test('reads the server body and puts the newest first', () {
      final rows = parseApiTokens(const {
        'tokens': [
          {'id': 'old_pat', 'name': 'old', 'createdAt': '2026-01-01T00:00:00.000Z'},
          {'id': 'new_pat', 'name': 'new', 'createdAt': '2026-08-01T00:00:00.000Z'},
        ],
      });

      // The token someone just minted is the one they are looking for.
      expect([for (final row in rows) row.id], ['new_pat', 'old_pat']);
    });

    test('skips a row it cannot read rather than losing the list', () {
      // One malformed row must not cost the operator the list they came here
      // to revoke something from.
      final rows = parseApiTokens(const {
        'tokens': [
          {'name': 'no id at all'},
          'not even a map',
          {'id': 'good_pat', 'name': 'good'},
        ],
      });

      expect([for (final row in rows) row.id], ['good_pat']);
    });

    test('a null expiry stays null', () {
      final row = parseApiTokens(const {
        'tokens': [
          {'id': 'a_pat', 'expiresAt': null},
        ],
      }).single;

      expect(row.expiresAt, isNull);
      expect(row.statusAt(_now), ApiTokenStatus.live);
    });
  });

  group('the mint draft', () {
    test('will not mint without a name, a collection and an operation', () {
      expect(const ApiTokenDraft().refusal, contains('name'));
      expect(const ApiTokenDraft(name: 'backup').refusal, contains('collection'));
      expect(const ApiTokenDraft(name: 'backup', tables: 'orders', operations: {}).refusal, contains('operation'));
      expect(const ApiTokenDraft(name: 'backup', tables: 'orders').refusal, isNull);
    });

    test('offers the reads before the writes', () {
      // `TableOperation.values` puts create/update/delete first, and a form
      // whose first three checkboxes are the writes invites a wider token than
      // the person meant.
      expect(apiTokenOperations.take(3), ['view', 'list', 'count']);
      expect(apiTokenOperations.skip(3).toSet(), apiTokenWriteOperations);
    });

    test('is an admin token by default, matching the CLI', () {
      expect(const ApiTokenDraft().admin, isTrue);
      expect(const ApiTokenDraft().operations, {'view', 'list', 'count'});
      expect(const ApiTokenDraft().expiry, ApiTokenExpiry.never);
    });

    test('sends the operations in the offered order, not the typed order', () {
      final body = const ApiTokenDraft(
        name: 'backup',
        tables: 'orders',
        operations: {'delete', 'view'},
      ).toRequestBody(now: _now);

      expect(body['operations'], ['view', 'delete']);
    });

    test('trims the name and splits the collections', () {
      final body = const ApiTokenDraft(
        name: '  nightly-backup  ',
        tables: ' orders , line_items ,, ',
      ).toRequestBody(now: _now);

      expect(body['name'], 'nightly-backup');
      expect(body['tables'], ['orders', 'line_items']);
    });

    test('sends no canEdit at all', () {
      // The server derives it from the granted operations. A screen that sent
      // its own answer would have to be kept in step with a rule it does not
      // own.
      final body = const ApiTokenDraft(
        name: 'writer',
        tables: 'orders',
        operations: {'create'},
      ).toRequestBody(now: _now);

      expect(body.containsKey('canEdit'), isFalse);
    });

    test('never means a null expiry, not a far-off one', () {
      expect(const ApiTokenDraft(name: 'backup', tables: 'orders').toRequestBody(now: _now)['expiresAt'], isNull);

      final dated = const ApiTokenDraft(
        name: 'backup',
        tables: 'orders',
        expiry: ApiTokenExpiry.days90,
      ).toRequestBody(now: _now);

      expect(DateTime.parse(dated['expiresAt']! as String), _now.add(const Duration(days: 90)));
    });

    test('an unknown expiry name falls back to never', () {
      // A value from a stale client, or a hand-edited select. Falling back to
      // the widest expiry is safe here in a way it would not be for a scope:
      // the token is still revocable, and guessing a duration would silently
      // kill an integration on a date nobody chose.
      expect(ApiTokenExpiry.fromName('fortnight'), ApiTokenExpiry.never);
    });
  });

  group('the operations wildcard', () {
    test('describeScope spells it out the way it does for collections', () {
      // Same reason: the widest grant on the page must not be the smallest
      // glyph on it. Someone scanning for the credential with too much reach
      // should not have to know that one asterisk is the wide one.
      final line = describeScope(
        const ApiTokenScopeView(
          tables: ['orders'],
          operations: ['*'],
          customOperations: [],
          admin: true,
          canEdit: true,
        ),
      );

      expect(line, 'orders · every operation');
      expect(line, isNot(contains('*')));
    });

    test('the draft sends ["*"] instead of the ticked boxes', () {
      const draft = ApiTokenDraft(name: 'backup', tables: 'orders', operations: {'view'}, allOperations: true);

      expect(draft.toRequestBody(now: _now)['operations'], ['*']);
    });

    test('it satisfies the "choose an operation" refusal on its own', () {
      const draft = ApiTokenDraft(name: 'backup', tables: 'orders', operations: {}, allOperations: true);

      expect(draft.refusal, isNull);
    });

    test('unticking it restores the boxes rather than clearing them', () {
      // The ticks are kept while the wildcard is on, so turning it off is not
      // a way to lose the choice somebody had already made.
      const draft = ApiTokenDraft(name: 'backup', tables: 'orders', operations: {'view', 'count'}, allOperations: true);

      final off = draft.copyWith(allOperations: false);

      expect(off.operations, {'view', 'count'});
      expect(off.toRequestBody(now: _now)['operations'], ['view', 'count']);
    });
  });
}
