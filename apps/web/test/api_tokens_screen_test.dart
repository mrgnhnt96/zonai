import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_web/components/api_tokens_screen.dart';
import 'package:zonai_web/components/theme/zonai_tag.dart';
import 'package:zonai_web/utils/api_tokens.dart';

/// Component tests for the API Tokens screen.
///
/// [ApiTokensPanel] is pure, so these pump it directly: no provider scope, no
/// server, no session. What is being pinned is what a screenshot cannot tell
/// you — that the reveal says the credential is unrecoverable, that a revoked
/// token's control is genuinely disabled rather than merely styled that way,
/// and that a failed load does not read as "no tokens".
///
/// The disabled assertions read `button.disabled` rather than clicking and
/// expecting nothing: in a browser a disabled button emits no click event, but
/// `tester.click` invokes the handler directly, so a click-based test would
/// fail against a correctly disabled control and pass against one that only
/// looks disabled. Same note as `admins_screen_test.dart`.
final _now = DateTime.utc(2026, 8, 24, 12);

ApiTokenRow _row({String id = 'abc123_pat', String name = 'nightly-backup', DateTime? revokedAt, DateTime? expiresAt}) {
  return ApiTokenRow(
    id: id,
    name: name,
    tokenPrefix: 'zonai_pat_qT501Hoh',
    scope: const ApiTokenScopeView(
      tables: ['orders'],
      operations: ['view', 'list'],
      customOperations: [],
      admin: true,
      canEdit: false,
    ),
    createdAt: _now.subtract(const Duration(days: 3)),
    expiresAt: expiresAt,
    revokedAt: revokedAt,
  );
}

Component _panel({
  List<ApiTokenRow> tokens = const [],
  ApiTokenDraft draft = const ApiTokenDraft(),
  List<String> collections = const ['orders', 'line_items', 'users'],
  ({ApiTokenRow row, String secret})? revealed,
  bool isLoading = false,
  String? loadError,
  bool isMinting = false,
  Set<String> busyIds = const {},
  void Function()? onDismissReveal,
  void Function(ApiTokenRow row)? onRevoke,
  void Function(ApiTokenRow row)? onDelete,
  void Function()? onMint,
  void Function(ApiTokenDraft draft)? onDraftChanged,
}) {
  return ApiTokensPanel(
    tokens: tokens,
    draft: draft,
    collections: collections,
    revealed: revealed,
    now: _now,
    isLoading: isLoading,
    loadError: loadError,
    isMinting: isMinting,
    busyIds: busyIds,
    onDraftChanged: onDraftChanged ?? (_) {},
    onMint: onMint ?? () {},
    onDismissReveal: onDismissReveal ?? () {},
    onRevoke: onRevoke ?? (_) {},
    onDelete: onDelete ?? (_) {},
  );
}

List<button> _buttonsLabelled(String text) {
  return [for (final element in find.componentWithText(button, text).evaluate()) element.component as button];
}

void main() {
  group('the list', () {
    testComponents('shows each token with its scope, status and timeline', (tester) async {
      tester.pumpComponent(
        _panel(
          tokens: [
            _row(),
            _row(id: 'def_pat', name: 'vercel-preview'),
          ],
        ),
      );

      expect(find.text('Issued tokens (2)'), findsOneComponent);
      expect(find.text('nightly-backup'), findsOneComponent);
      expect(find.text('vercel-preview'), findsOneComponent);
      expect(find.textContaining('orders · view, list'), findsNComponents(2));
      expect(find.textContaining('never expires'), findsNComponents(2));
    });

    testComponents('keeps a revoked token visible, labelled and un-revokable', (tester) async {
      // Hiding it would turn "revoked" into "vanished", and a credential that
      // stopped working is exactly the row somebody is looking for when an
      // integration breaks.
      tester.pumpComponent(_panel(tokens: [_row(revokedAt: _now.subtract(const Duration(days: 1)))]));

      expect(find.text('nightly-backup'), findsOneComponent);
      expect(find.text('Revoked'), findsOneComponent);
      expect(find.textContaining('Already revoked'), findsOneComponent);
      expect(_buttonsLabelled('Revoke').single.disabled, isTrue);
      // Delete stays available: removing the record is the other thing, and it
      // is the only thing left to do with this row.
      expect(_buttonsLabelled('Delete').single.disabled, isFalse);
    });

    testComponents('an expired token is expired, not revoked', (tester) async {
      tester.pumpComponent(_panel(tokens: [_row(expiresAt: _now.subtract(const Duration(days: 1)))]));

      expect(find.text('Expired'), findsOneComponent);
      expect(find.text('Revoked'), findsNothing);
      // Still revokable: expiry is the clock's answer and revocation is a
      // person's, and withdrawing a lapsed credential is a reasonable thing
      // to want on the record.
      expect(_buttonsLabelled('Revoke').single.disabled, isFalse);
    });

    testComponents('says there are none rather than showing an empty box', (tester) async {
      tester.pumpComponent(_panel());

      expect(find.text('No API tokens yet.'), findsOneComponent);
    });

    testComponents('surfaces a load failure instead of an empty list', (tester) async {
      // An empty list and a failed request look identical otherwise, and one
      // of them means every integration on this deployment is unaccounted for.
      tester.pumpComponent(_panel(loadError: 'Forbidden'));

      expect(find.text('Could not load API tokens'), findsOneComponent);
      expect(find.text('Forbidden'), findsOneComponent);
      expect(_buttonsLabelled('Create token'), isEmpty);
    });

    testComponents('does not fire a second revoke while the first is travelling', (tester) async {
      tester.pumpComponent(_panel(tokens: [_row()], busyIds: {'abc123_pat'}));

      expect(_buttonsLabelled('Working…').single.disabled, isTrue);
    });
  });

  group('the reveal', () {
    testComponents('shows the plaintext and says it will not be shown again', (tester) async {
      // The load-bearing assertion on this screen. `POST /admin/tokens`
      // returns the credential exactly once — the row keeps only its SHA-256 —
      // so an operator who navigates away without copying it is left with a
      // live, never-expiring token they can only revoke.
      tester.pumpComponent(_panel(revealed: (row: _row(), secret: 'zonai_pat_qT501HohVqtce6xB_EmC9W1lCBnhlDq')));

      expect(find.text('Copy "nightly-backup" now'), findsOneComponent);
      expect(find.text('zonai_pat_qT501HohVqtce6xB_EmC9W1lCBnhlDq'), findsOneComponent);
      expect(find.textContaining('only time it will be shown'), findsOneComponent);
      expect(find.textContaining('cannot be recovered'), findsOneComponent);
    });

    testComponents('is dismissed deliberately, not on a timer', (tester) async {
      var dismissed = 0;
      tester.pumpComponent(
        _panel(revealed: (row: _row(), secret: 'zonai_pat_secret'), onDismissReveal: () => dismissed++),
      );

      final confirm = _buttonsLabelled('I have copied it');
      expect(confirm, hasLength(1));

      await tester.click(find.componentWithText(button, 'I have copied it'));
      expect(dismissed, 1);
    });

    testComponents('is absent until something has been minted', (tester) async {
      tester.pumpComponent(_panel(tokens: [_row()]));

      expect(find.textContaining('only time it will be shown'), findsNothing);
    });
  });

  group('the mint form', () {
    testComponents('states why it cannot be submitted, before it is clicked', (tester) async {
      tester.pumpComponent(_panel(draft: const ApiTokenDraft()));

      expect(_buttonsLabelled('Create token').single.disabled, isTrue);
      expect(find.textContaining('unnamed credential'), findsOneComponent);
    });

    testComponents('enables itself once the draft is complete', (tester) async {
      var minted = 0;
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'nightly-backup', tables: 'orders'),
          onMint: () => minted++,
        ),
      );

      expect(_buttonsLabelled('Create token').single.disabled, isFalse);
      await tester.click(find.componentWithText(button, 'Create token'));
      expect(minted, 1);
    });

    testComponents('explains what admin does while it is on', (tester) async {
      // The one piece of copy that stops a first token reading as broken: the
      // default rules deny everyone but an admin, and the failure shows up
      // nowhere near this checkbox.
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders'),
        ),
      );

      expect(find.textContaining('It is not a bypass'), findsOneComponent);
    });

    testComponents('explains what turning admin off costs', (tester) async {
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders', admin: false),
        ),
      );

      expect(find.textContaining('denied by the default rules'), findsOneComponent);
    });

    testComponents('cannot be submitted twice while a mint is in flight', (tester) async {
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders'),
          isMinting: true,
        ),
      );

      expect(_buttonsLabelled('Creating…').single.disabled, isTrue);
    });
  });

  group('the mint form, bound to an auth row', () {
    // The bound form is the same component the screen renders; what a test can
    // pin without a browser is that it SAYS what it is bound to. The binding
    // is the one field nobody can edit, and a form that did not show it would
    // look identical to the unbound one.
    testComponents('names the row it will act as', (tester) async {
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(
            name: 'users-abc123_usr',
            tables: 'orders',
            boundTable: 'users',
            boundUserId: 'abc123_usr',
          ),
        ),
      );

      expect(find.text('users/abc123_usr'), findsOneComponent);
      expect(find.textContaining('Acts as'), findsOneComponent);
      // The consequence, not just the fact: a bound token is clamped to the
      // row's own admin grant at resolution, and somebody minting one from a
      // row panel is exactly who needs to know that.
      expect(find.textContaining('never be more of an admin'), findsOneComponent);
    });

    testComponents('says nothing about a binding when there is none', (tester) async {
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders'),
        ),
      );

      expect(find.textContaining('Acts as'), findsNothing);
    });
  });

  group('the operations wildcard', () {
    testComponents('ticks and disables all six, so the display cannot lie', (tester) async {
      // Under `*` the token really can do all six, so showing them unticked
      // would be false. Showing them ticked and ENABLED would be worse: the
      // next click would send a narrower scope than the one on screen.
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders', operations: {'view'}, allOperations: true),
        ),
      );

      // Read off the rendered DOM rather than the component: `input<bool>`
      // builds a DomComponent, so a cast back to `input` fails.
      final boxes = [
        for (final element in find.tag('input').evaluate())
          if (element.component case final DomComponent dom) dom,
      ].where((dom) => dom.attributes?['type'] == 'checkbox').toList();

      // Six operations + "Every operation" + "Admin".
      expect(boxes.length, 8);
      for (final box in boxes.take(6)) {
        expect(box.attributes?['checked'], isNotNull);
        expect(box.attributes?['disabled'], 'disabled');
      }
      // The wildcard's own box stays live -- it is how the choice is undone.
      expect(boxes[6].attributes?['disabled'], isNull);
      expect(find.textContaining('a later zonai adds'), findsOneComponent);
    });
  });
  group('the collections field', () {
    // The value on the wire did not change -- still a comma-separated string,
    // still `*` -- so what these pin is the authoring gesture: what the
    // dropdown offers, what became a pill, and that the two never disagree.
    //
    // Everything here is addressed by id or aria-label rather than by tag:
    // the mint form carries a SECOND select (the expiry), so `find.tag`
    // silently matches the wrong control -- it did, while these were written.
    Finder collectionsSelect() => find.byComponentPredicate(
      (c) => c is DomComponent && c.tag == 'select' && c.id == 'api-token-tables',
      description: 'the collections <select>',
    );

    Finder removeButton(String name) => find.byComponentPredicate(
      (c) => c is DomComponent && c.tag == 'button' && c.attributes?['aria-label'] == 'Remove $name',
      description: 'the remove control for $name',
    );

    // Every <option> on the form, not just this select's. Reading the select's
    // own `children` returns nothing -- the options are built into the element
    // tree, not held on the parent DomComponent -- and the expiry select's
    // values ('30d' and friends) cannot collide with a collection name, so a
    // page-wide scan answers the same question.
    List<String> optionValues() => [
      for (final element in find.tag('option').evaluate())
        if (element.component case final DomComponent dom) dom.attributes?['value'] ?? '',
    ];

    testComponents('offers every collection and the wildcard when none are picked', (tester) async {
      tester.pumpComponent(_panel(collections: const ['orders', 'line_items']));

      expect(optionValues(), containsAll(<String>['*', 'orders', 'line_items']));
      // Empty is a real scope, not an unfilled field, and it grants nothing.
      expect(find.textContaining('this token would reach none'), findsOneComponent);
    });

    testComponents('a picked collection leaves the dropdown and becomes a pill', (tester) async {
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders'),
          collections: const ['orders', 'line_items'],
        ),
      );

      // Offering it again would let the same grant be added twice.
      expect(optionValues(), isNot(contains('orders')));
      expect(optionValues(), contains('line_items'));
      expect(removeButton('orders'), findsOneComponent);
    });

    testComponents('removing a pill drops only that collection', (tester) async {
      ApiTokenDraft? changed;
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: 'orders,line_items'),
          collections: const ['orders', 'line_items'],
          onDraftChanged: (draft) => changed = draft,
        ),
      );

      // The closure is invoked directly rather than clicked: ZonaiTag's remove
      // handler calls `event.stopPropagation()`, and universal_web throws
      // "Cannot use web or js_interop apis on native platforms" the moment a
      // VM component test dispatches a real click at it. What is being pinned
      // is which name the field drops, and that lives in this closure.
      final tag =
          find
                  .byComponentPredicate((c) => c is ZonaiTag && c.label == 'orders', description: 'the orders pill')
                  .evaluate()
                  .single
                  .component
              as ZonaiTag;
      tag.onRemove!();

      expect(changed?.tables, 'line_items');
    });

    testComponents('offers the app\'s own collections before zonai\'s internals', (tester) async {
      // A flat list puts `_api_tokens` beside `orders` as though granting them
      // were the same kind of decision. The sidebar keeps system tables behind
      // an expander; this keeps them last. They stay reachable either way.
      tester.pumpComponent(_panel(collections: const ['_api_tokens', 'orders', '_abusers', 'line_items']));

      final values = optionValues().where((v) => v != '').toList();
      expect(values.indexOf('orders'), lessThan(values.indexOf('_api_tokens')));
      expect(values.indexOf('line_items'), lessThan(values.indexOf('_abusers')));
      expect(values, containsAll(<String>['_api_tokens', '_abusers']));
    });

    testComponents('the wildcard shows one pill and no dropdown to widen it further', (tester) async {
      // There is nothing to add to "every collection", and a control that
      // cannot do anything on a scope form reads as a control that failed.
      tester.pumpComponent(
        _panel(
          draft: const ApiTokenDraft(name: 'backup', tables: '*'),
          collections: const ['orders', 'line_items'],
        ),
      );

      expect(collectionsSelect(), findsNothing);
      expect(find.text('* \u2014 every collection'), findsOneComponent);
      expect(removeButton('orders'), findsNothing);
    });
  });
}
