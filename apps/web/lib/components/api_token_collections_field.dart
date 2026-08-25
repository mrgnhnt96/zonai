import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../utils/sqlite_table_utils.dart';
import '../utils/table_cell_edit.dart';
import 'theme/ui_styles.dart';
import 'theme/zonai_select.dart';
import 'theme/zonai_tag.dart';

/// The `Collections` control on the API token mint form.
///
/// Replaces a free-text comma list. The stored value is unchanged -- still a
/// comma-separated string, still `*` for the wildcard -- because that string is
/// what `ApiTokenDraft.tables` carries and what the request body sends. Only
/// the authoring gesture moved.
///
/// The dropdown offers the collections NOT yet picked, so choosing one is
/// always additive and a name can never be granted twice. Picking `*` replaces
/// the whole selection rather than joining it: `["*", "orders"]` invites the
/// reader to guess whether the token is scoped to orders or to everything, and
/// the wildcard is stored rather than expanded (see docs/api-tokens.md,
/// "The wildcard is stored, not expanded"), so the two are not interchangeable.
///
/// [collections] is INJECTED rather than read from `sqliteTablesProvider`
/// here, because this field renders inside [ApiTokensPanel], which is pure on
/// purpose -- its tests pump it with no provider scope at all, and a provider
/// read in here would throw in every one of them. The screen and the bound
/// dialog each read the provider and hand the list down.
///
/// The list is the sidebar's, so anything visible in the dashboard is
/// grantable here. That is also the limit worth naming: a collection this
/// dashboard cannot see is no longer typeable, which the free-text field
/// allowed.
class ApiTokenCollectionsField extends StatelessComponent {
  const ApiTokenCollectionsField({
    super.key,
    required this.id,
    required this.value,
    required this.collections,
    required this.onChanged,
    this.disabled = false,
  });

  final String id;

  /// Comma-separated collection names, or `*`.
  final String value;

  /// Every collection that may be granted, in sidebar order.
  final List<String> collections;

  final void Function(String value) onChanged;
  final bool disabled;

  static const _wildcard = '*';
  static const _wildcardLabel = '* — every collection';

  @override
  Component build(BuildContext context) {
    final selected = parseCommaSeparatedList(value);
    final isWildcard = selected.contains(_wildcard);
    // The app's own collections first, zonai's `_`-prefixed internals after --
    // the same split the sidebar draws, where system tables live behind an
    // expander rather than inline. A flat list puts `_api_tokens` next to
    // `orders` as though granting them were the same kind of decision. They
    // stay reachable (the free-text field this replaced allowed them, and
    // removing a grant anyone might already rely on is not this change's job);
    // they are just no longer the first thing the list offers.
    final unpicked = [
      for (final name in collections)
        if (!selected.contains(name)) name,
    ];
    final available = [
      for (final name in unpicked)
        if (!isSystemSqliteTable(name)) name,
      for (final name in unpicked)
        if (isSystemSqliteTable(name)) name,
    ];

    return div(classes: ZonaiClasses.field, [
      label(htmlFor: id, classes: ZonaiClasses.label, [.text('Collections')]),

      // Gone rather than disabled under the wildcard: there is nothing left to
      // add to "every collection", and a control that cannot do anything is
      // noise on a form whose whole job is to say what the token may reach.
      if (!isWildcard)
        ZonaiSelect(
          id: id,
          // Always empty. This select is an action, not a value -- what it
          // holds after a pick is a pill, and leaving the name in the closed
          // control would read as "scoped to that one".
          value: '',
          placeholder: available.isEmpty ? 'Every collection is already picked' : 'Add a collection…',
          disabled: disabled || (available.isEmpty && selected.isNotEmpty),
          options: [
            const ZonaiSelectOption(value: _wildcard, label: _wildcardLabel),
            for (final name in available) ZonaiSelectOption(value: name, label: name),
          ],
          onChange: (picked) {
            if (picked.isEmpty) return;
            if (picked == _wildcard) {
              onChanged(_wildcard);
              return;
            }
            onChanged(joinCommaSeparatedList([...selected, picked]));
          },
        ),

      if (selected.isNotEmpty)
        div(classes: 'z-token-collections', [
          for (final name in selected)
            ZonaiTag(
              label: name == _wildcard ? _wildcardLabel : name,
              monospace: name != _wildcard,
              onRemove: disabled
                  ? null
                  : () => onChanged(joinCommaSeparatedList([...selected.where((each) => each != name)])),
            ),
        ]),

      // Says what an empty selection MEANS. Empty is a real state here -- a
      // token with no collections reaches none -- and without this the field
      // reads as merely unfilled.
      if (selected.isEmpty)
        p(classes: 'z-token-collections-empty', [.text('No collections yet — this token would reach none.')]),
    ]);
  }
}

@css
List<StyleRule> apiTokenCollectionsFieldStyles = [
  css('.z-token-collections').styles(
    display: .flex,
    flexWrap: FlexWrap.wrap,
    gap: Gap.all(ZonaiSpacing.s3),
    margin: .only(top: ZonaiSpacing.s4),
  ),
  css('.z-token-collections-empty').styles(
    margin: .only(top: ZonaiSpacing.s3),
    fontSize: 0.8125.rem,
    color: mutedColor,
  ),
];
