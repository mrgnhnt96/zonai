import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../constants/button_sizes.dart';
import '../providers/api_tokens_provider.dart';
import '../providers/home_ui_provider.dart';
import '../utils/api_tokens.dart';
import '../utils/user_facing_error.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/zonai_button.dart';
import 'theme/zonai_icon_button.dart';
import 'theme/zonai_select.dart';
import 'theme/zonai_text_field.dart';
import 'toast_overlay.dart';

/// The API Tokens screen (`docs/api-tokens-design.md` §11 step 8): every
/// credential this deployment has issued, and the controls to issue and
/// withdraw them.
///
/// **The reveal is the load-bearing part.** `POST /admin/tokens` returns the
/// plaintext exactly once — the row keeps only its SHA-256, so there is
/// nothing on the server to read it back out of, here or anywhere. A screen
/// that lost it to a re-render or a navigation would leave the operator with a
/// live, never-expiring credential they cannot use and can only revoke. So the
/// secret is held in this state, is shown until dismissed, and says out loud
/// that it will not be shown again.
///
/// Split the same way [AdminsScreen] is: this half is wired — sidebar,
/// providers, the draft being typed — and [ApiTokensPanel] below is pure.
/// Given rows, a draft and callbacks it renders the whole page and decides
/// nothing it was not handed, which is what lets a test pin the statuses and
/// the disabled controls without a server or a browser.
class ApiTokensScreen extends StatefulComponent {
  const ApiTokensScreen({super.key});

  @override
  State<ApiTokensScreen> createState() => _ApiTokensScreenState();
}

class _ApiTokensScreenState extends State<ApiTokensScreen> {
  ApiTokenDraft _draft = const ApiTokenDraft();

  /// The plaintext of the token just minted, and the row it belongs to.
  ///
  /// Held here rather than in [apiTokensProvider], deliberately: that
  /// notifier's state is rebuilt from the server on every `invalidateSelf`,
  /// and a value the server cannot produce a second time must not live
  /// somewhere that expects to re-fetch it.
  ({ApiTokenRow row, String secret})? _revealed;

  bool _minting = false;

  /// Token ids with an action in flight, so a second click cannot fire the
  /// same revoke or delete twice while the first is still travelling.
  final _busy = <String>{};

  @override
  Component build(BuildContext context) {
    final mobileNavOpen = context.watch(homeUiProvider).mobileNavOpen;
    final isClient = context.binding.isClient;

    // Same guard the Admins screen uses: the list is fetched with the caller's
    // bearer token, which SSR does not have, and a provider that resolves
    // after the server render has no frame to land in.
    final tokens = isClient ? context.watch(apiTokensProvider) : const AsyncValue<List<ApiTokenRow>>.loading();

    return main_(classes: 'home${mobileNavOpen ? ' home--mobile-nav-open' : ''}', [
      HomeSidebar(focused: null),
      div(classes: 'home-main', [
        div(classes: 'home-mobile-nav-header', [
          ZonaiIconButton(
            size: ZonaiIconButtonSize.lg,
            attributes: {'aria-label': 'Open navigation', 'aria-expanded': mobileNavOpen ? 'true' : 'false'},
            onClick: () => context.read(homeUiProvider.notifier).toggleMobileNav(),
            child: .text('☰'),
          ),
          h1(classes: 'home-mobile-nav-title', [.text('API tokens')]),
        ]),
        div(classes: 'dashboard-scroller', [
          div(classes: 'dashboard', [
            ApiTokensPanel(
              tokens: tokens.value ?? const [],
              draft: _draft,
              revealed: _revealed,
              now: DateTime.now(),
              isLoading: tokens.isLoading && !tokens.hasValue,
              loadError: tokens.hasError ? userFacingError(tokens.error!) : null,
              isMinting: _minting,
              busyIds: _busy,
              onDraftChanged: (draft) => setState(() => _draft = draft),
              onMint: _mint,
              onDismissReveal: () => setState(() => _revealed = null),
              onRevoke: (row) =>
                  _run(row.id, () => context.read(apiTokensProvider.notifier).revoke(id: row.id, name: row.name)),
              onDelete: (row) =>
                  _run(row.id, () => context.read(apiTokensProvider.notifier).delete(id: row.id, name: row.name)),
            ),
          ]),
        ]),
      ]),
      if (mobileNavOpen)
        div(
          classes: 'home-mobile-backdrop',
          attributes: {'aria-hidden': 'true'},
          events: {'click': (_) => context.read(homeUiProvider.notifier).closeMobileNav()},
          [],
        ),
      const HomeSettingsOverlay(),
      if (isClient) const ToastOverlay(),
    ]);
  }

  Future<void> _mint() async {
    if (_minting || _draft.refusal != null) return;
    setState(() => _minting = true);
    try {
      final minted = await context.read(apiTokensProvider.notifier).mint(_draft.toRequestBody(now: DateTime.now()));
      if (!mounted) return;
      if (minted != null) {
        // The form resets and the reveal opens in the same frame: a form still
        // holding the previous name invites a second, accidental mint of the
        // credential now sitting unread on the screen.
        setState(() {
          _revealed = minted;
          _draft = const ApiTokenDraft();
        });
      }
    } finally {
      if (mounted) setState(() => _minting = false);
    }
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }
}

/// Everything the API Tokens screen draws, as a function of what it is given.
class ApiTokensPanel extends StatelessComponent {
  const ApiTokensPanel({
    super.key,
    required this.tokens,
    required this.draft,
    required this.now,
    required this.onDraftChanged,
    required this.onMint,
    required this.onDismissReveal,
    required this.onRevoke,
    required this.onDelete,
    this.revealed,
    this.isLoading = false,
    this.loadError,
    this.isMinting = false,
    this.busyIds = const {},
  });

  final List<ApiTokenRow> tokens;
  final ApiTokenDraft draft;

  /// The plaintext just minted, or null when there is nothing to reveal.
  final ({ApiTokenRow row, String secret})? revealed;

  final DateTime now;
  final void Function(ApiTokenDraft draft) onDraftChanged;
  final void Function() onMint;
  final void Function() onDismissReveal;
  final void Function(ApiTokenRow row) onRevoke;
  final void Function(ApiTokenRow row) onDelete;
  final bool isLoading;
  final String? loadError;
  final bool isMinting;
  final Set<String> busyIds;

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      div(classes: 'dashboard-header', [
        h1(classes: 'dashboard-title', [.text('API tokens')]),
      ]),
      if (revealed case final minted?) _RevealPanel(minted: minted, onDismiss: onDismissReveal),
      if (loadError case final error?)
        div(classes: 'dashboard-panel', [
          p(classes: 'dashboard-panel-title', [.text('Could not load API tokens')]),
          pre(classes: 'z-alert__body', [.text(error)]),
        ])
      else
        div(classes: 'dashboard-row dashboard-row--split', [
          div(classes: 'dashboard-panel z-admins-panel', [
            p(classes: 'dashboard-panel-title', [.text('New token')]),
            ApiTokenMintForm(draft: draft, pending: isMinting, onChanged: onDraftChanged, onSubmit: onMint),
          ]),
          div(classes: 'dashboard-panel z-admins-panel', [
            p(classes: 'dashboard-panel-title', [
              .text(tokens.isEmpty ? 'Issued tokens' : 'Issued tokens (${tokens.length})'),
            ]),
            if (isLoading && tokens.isEmpty)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
            else if (tokens.isEmpty)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('No API tokens yet.')])
            else
              div(classes: 'z-admins-list', [
                for (final row in tokens)
                  _TokenRow(
                    row: row,
                    now: now,
                    busy: busyIds.contains(row.id),
                    onRevoke: () => onRevoke(row),
                    onDelete: () => onDelete(row),
                  ),
              ]),
          ]),
        ]),
    ]);
  }
}

/// The mint form. Controlled — it holds no state of its own — so a test can
/// pump it with a finished draft and click.
class ApiTokenMintForm extends StatelessComponent {
  const ApiTokenMintForm({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onSubmit,
    this.pending = false,
  });

  final ApiTokenDraft draft;
  final void Function(ApiTokenDraft draft) onChanged;
  final void Function() onSubmit;
  final bool pending;

  @override
  Component build(BuildContext context) {
    final refusal = draft.refusal;

    return div(classes: 'z-token-form', [
      ZonaiTextField(
        id: 'api-token-name',
        fieldLabel: 'Name',
        value: draft.name,
        placeholder: 'nightly-backup',
        autocomplete: 'off',
        disabled: pending,
        onInput: (value) => onChanged(draft.copyWith(name: value)),
      ),
      ZonaiTextField(
        id: 'api-token-tables',
        fieldLabel: 'Collections',
        value: draft.tables,
        placeholder: 'orders, line_items — or * for every one',
        autocomplete: 'off',
        disabled: pending,
        onInput: (value) => onChanged(draft.copyWith(tables: value)),
      ),
      fieldset(classes: 'z-token-ops', [
        legend(classes: 'z-token-ops-legend', [.text('Operations')]),
        for (final operation in apiTokenOperations)
          label(classes: 'z-token-op', [
            input<bool>(
              type: InputType.checkbox,
              checked: draft.operations.contains(operation),
              attributes: {if (pending) 'disabled': 'disabled'},
              onChange: (_) => onChanged(
                draft.copyWith(
                  operations: {
                    for (final existing in draft.operations)
                      if (existing != operation) existing,
                    if (!draft.operations.contains(operation)) operation,
                  },
                ),
              ),
            ),
            .text(operation),
          ]),
      ]),
      label(classes: 'z-token-op z-token-admin', [
        input<bool>(
          type: InputType.checkbox,
          checked: draft.admin,
          attributes: {if (pending) 'disabled': 'disabled'},
          onChange: (_) => onChanged(draft.copyWith(admin: !draft.admin)),
        ),
        .text('Admin'),
      ]),
      // The one piece of copy on this screen that stops a first token reading
      // as broken. The default rules deny everyone but an admin, so a token
      // without it is inert against most collections — and the failure looks
      // like a bug in the rules, nowhere near this checkbox.
      p(classes: 'z-admins-note', [
        .text(
          draft.admin
              ? 'Admin lets the token satisfy the default rules, which deny everyone else. '
                    'It is not a bypass — the collections and operations above still bound it.'
              : 'Without admin this token is denied by the default rules, so it can only reach '
                    'collections whose rules admit it explicitly.',
        ),
      ]),
      div(classes: 'z-token-expiry', [
        label(classes: 'z-token-ops-legend', attributes: const {'for': 'api-token-expiry'}, [.text('Expires')]),
        ZonaiSelect(
          id: 'api-token-expiry',
          value: draft.expiry.name,
          disabled: pending,
          options: [
            for (final expiry in ApiTokenExpiry.values) ZonaiSelectOption(value: expiry.name, label: expiry.label),
          ],
          onChange: (value) => onChanged(draft.copyWith(expiry: ApiTokenExpiry.fromName(value))),
        ),
      ]),
      if (refusal case final reason?) p(classes: 'z-admins-note', [.text(reason)]),
      ZonaiButton(
        fullWidth: true,
        disabled: pending || refusal != null,
        attributes: {if (refusal case final reason?) 'title': reason},
        onClick: onSubmit,
        child: .text(pending ? 'Creating…' : 'Create token'),
      ),
    ]);
  }
}

/// The copy-once reveal.
///
/// Not a toast and not a modal: a toast disappears on a timer and a modal is
/// dismissed by clicking anywhere, and both would destroy the only copy of a
/// credential that cannot be recovered. It stays until it is dismissed
/// deliberately, and it says why.
class _RevealPanel extends StatelessComponent {
  const _RevealPanel({required this.minted, required this.onDismiss});

  final ({ApiTokenRow row, String secret}) minted;
  final void Function() onDismiss;

  @override
  Component build(BuildContext context) {
    return div(classes: 'dashboard-panel z-token-reveal', [
      p(classes: 'dashboard-panel-title', [.text('Copy "${minted.row.name}" now')]),
      p(classes: 'z-admins-note', [
        .text(
          'This is the only time it will be shown. The server keeps only its hash, so it '
          'cannot be recovered — if you lose it, revoke this token and create another.',
        ),
      ]),
      // Selectable text rather than a copy button alone: a clipboard write can
      // fail silently in a browser that refused permission, and a value the
      // operator can see and select cannot be lost to that.
      pre(classes: 'z-token-secret', [
        code([.text(minted.secret)]),
      ]),
      ZonaiButton(variant: ZonaiButtonVariant.secondary, onClick: onDismiss, child: .text('I have copied it')),
    ]);
  }
}

class _TokenRow extends StatelessComponent {
  const _TokenRow({
    required this.row,
    required this.now,
    required this.busy,
    required this.onRevoke,
    required this.onDelete,
  });

  final ApiTokenRow row;
  final DateTime now;
  final bool busy;
  final void Function() onRevoke;
  final void Function() onDelete;

  @override
  Component build(BuildContext context) {
    final status = row.statusAt(now);
    final refusal = revokeRefusal(row);

    return div(classes: 'z-admins-row z-token-row', [
      div(classes: 'z-admins-row-text', [
        div(classes: 'z-token-row-head', [
          span(classes: 'z-admins-row-title', [.text(row.name)]),
          span(classes: 'z-token-status z-token-status--${status.name}', [.text(status.label)]),
        ]),
        span(classes: 'z-admins-note', [.text(describeScope(row.scope))]),
        span(classes: 'z-admins-note', [.text(describeTokenTimeline(row, now: now))]),
        if (row.tokenPrefix.isNotEmpty) span(classes: 'z-token-prefix', [.text('${row.tokenPrefix}…')]),
        if (refusal case final reason?) span(classes: 'z-admins-note', [.text(reason)]),
      ]),
      div(classes: 'z-token-row-actions', [
        ZonaiButton(
          variant: ZonaiButtonVariant.secondary,
          disabled: refusal != null || busy,
          attributes: {if (refusal case final reason?) 'title': reason},
          onClick: onRevoke,
          child: .text(busy ? 'Working…' : 'Revoke'),
        ),
        ZonaiButton(variant: ZonaiButtonVariant.secondary, disabled: busy, onClick: onDelete, child: .text('Delete')),
      ]),
    ]);
  }
}
