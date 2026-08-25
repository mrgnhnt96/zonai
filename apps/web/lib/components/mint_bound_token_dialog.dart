import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../constants/button_sizes.dart';
import '../providers/api_tokens_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../utils/api_tokens.dart';
import 'api_tokens_screen.dart' show ApiTokenMintForm, ApiTokenRevealPanel;
import 'theme/zonai_icon_button.dart';

/// Mints an API token **bound to one auth row**, from the row detail panel.
///
/// The same form the API Tokens screen uses, over a binding the operator
/// cannot type wrong: the panel is already standing on `<table>/<id>`, so the
/// dialog is handed both and shows them rather than asking for them.
///
/// Bound, this is a personal access token — `jwt.userId` is that row, so every
/// ownership rule already written (`row.userId == jwt.userId`) matches without
/// a claim being invented for it. `ApiTokenScope.clampedTo` then holds it to
/// the row's own admin grant at *resolution*, so a token for an ordinary user
/// is not an admin key however wide the scope on its row says it is.
///
/// **The reveal lives here, in this dialog's `State`** — the same rule the API
/// Tokens screen follows and for the same reason. `apiTokensProvider` is
/// rebuilt from the server on every `invalidateSelf`, and `mint` invalidates
/// it, so a secret parked there would be thrown away by the refresh that the
/// minting itself triggers. There is no second copy on the server to recover.
class MintBoundTokenDialog extends StatefulComponent {
  const MintBoundTokenDialog({super.key, required this.table, required this.rowId, required this.onClose});

  /// The collection the row lives in, as `/db` names it.
  final String table;

  /// The row's id value — what `boundUserId` is checked against.
  final String rowId;

  final void Function() onClose;

  @override
  State<MintBoundTokenDialog> createState() => _MintBoundTokenDialogState();
}

class _MintBoundTokenDialogState extends State<MintBoundTokenDialog> {
  late ApiTokenDraft _draft = ApiTokenDraft(
    // Named after the row it acts as, because that is the fact somebody
    // revoking it six months from now needs and cannot otherwise recover:
    // the token list shows the binding, but only this row's id says *which*
    // account went missing. Editable — it is a default, not a decision.
    name: '${component.table}-${component.rowId}',
    boundTable: component.table,
    boundUserId: component.rowId,
  );

  ({ApiTokenRow row, String secret})? _revealed;
  bool _minting = false;

  Future<void> _mint() async {
    if (_minting || _draft.refusal != null) return;
    setState(() => _minting = true);
    try {
      final minted = await context.read(apiTokensProvider.notifier).mint(_draft.toRequestBody(now: DateTime.now()));
      if (!mounted) return;
      if (minted != null) setState(() => _revealed = minted);
    } finally {
      if (mounted) setState(() => _minting = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final revealed = _revealed;

    return Component.fragment([
      // No dismiss-on-click. Everywhere else in this dashboard a backdrop
      // click closes the thing over it; here, once the reveal is open, that
      // gesture destroys the only copy of a credential — so the backdrop is
      // inert and closing is a deliberate press on a named control.
      div(classes: 'z-token-bound-backdrop', attributes: {'aria-hidden': 'true'}, [], events: const {}),
      div(
        classes: 'z-token-bound-dialog',
        attributes: {
          'role': 'dialog',
          'aria-modal': 'true',
          'aria-label': 'Create an API token for ${component.table}/${component.rowId}',
        },
        [
          div(classes: 'z-token-bound-dialog-header', [
            h2(classes: 'dashboard-panel-title', [.text(revealed == null ? 'New API token' : 'Copy it now')]),
            ZonaiIconButton(
              size: ZonaiIconButtonSize.sm,
              variant: ZonaiIconButtonVariant.ghost,
              attributes: {'aria-label': 'Close'},
              onClick: component.onClose,
              child: .text('×'),
            ),
          ]),
          if (revealed case final minted?)
            // The form is gone, not merely disabled. It is a mint button
            // sitting under an unread secret, and the reveal is what the
            // operator is here to read.
            ApiTokenRevealPanel(minted: minted, onDismiss: component.onClose)
          else
            ApiTokenMintForm(
              draft: _draft,
              collections: [for (final t in context.watch(sqliteTablesProvider).tables) t.sqliteName],
              pending: _minting,
              onChanged: (draft) => setState(() => _draft = draft),
              onSubmit: _mint,
            ),
        ],
      ),
    ]);
  }
}
