import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../constants/button_sizes.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/app_tooltip_provider.dart';
import '../providers/home_ui_provider.dart';
import '../providers/maintenance_provider.dart';
import 'app_tooltip_overlay.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/zonai_button.dart';
import 'theme/zonai_icon_button.dart';
import 'theme/zonai_select.dart';
import 'theme/zonai_text_field.dart';
import 'toast_overlay.dart';

/// Operator screen for "how much space is zonai using, and how much is left".
///
/// Separate from the dashboard for two reasons that point the same way: the
/// dashboard is read-only by contract, and collecting storage is expensive
/// enough that it must not ride the dashboard's metrics poll.
///
/// The destructive cleanup tools sit below the storage section, so the numbers
/// an operator is acting on are on screen above the buttons that change them.
/// Each one refreshes the storage section when it finishes.
class MaintenanceScreen extends StatelessComponent {
  const MaintenanceScreen({super.key});

  @override
  Component build(BuildContext context) {
    final mobileNavOpen = context.watch(homeUiProvider).mobileNavOpen;

    // Async providers must not notify after SSR completes (no frames on the server).
    final isClient = context.binding.isClient;
    final storage = isClient ? context.watch(storageMetricsProvider) : const AsyncValue<StorageMetrics?>.loading();
    final data = storage.value;
    final loading = storage.isLoading && !storage.hasValue;

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
          h1(classes: 'home-mobile-nav-title', [.text('Maintenance')]),
        ]),
        div(classes: 'dashboard-scroller', [
          div(classes: 'dashboard', [
            div(classes: 'dashboard-header', [
              h1(classes: 'dashboard-title', [.text('Maintenance')]),
              if (isClient)
                ZonaiIconButton(
                  size: ZonaiIconButtonSize.xs,
                  variant: ZonaiIconButtonVariant.ghost,
                  disabled: storage.isLoading,
                  attributes: {'aria-label': 'Refresh storage'},
                  events: storage.isLoading
                      ? null
                      : appTooltipEvents(context, text: 'Refresh storage', placement: AppTooltipPlacement.belowLeft),
                  onClick: () => context.read(storageMetricsProvider.notifier).refresh(),
                  child: .text('⟳'),
                ),
            ]),
            p(classes: 'maintenance-section-label', [.text('Storage')]),
            if (storage.hasError)
              div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
                .text('Could not load storage usage.'),
              ])
            else ...[
              div(classes: 'dashboard-stats', [
                _StatCard(
                  label: 'Databases',
                  value: data == null ? '—' : formatBytes(data.totalDatabaseBytes),
                  hint: 'Every SQLite file zonai owns, including its WAL sidecar',
                ),
                _StatCard(
                  label: 'Reclaimable',
                  value: data == null ? '—' : formatBytes(data.totalReclaimableBytes),
                  hint: 'Free inside the database files, not yet returned to the operating system',
                ),
                _StatCard(
                  label: 'Photos',
                  value: data == null ? '—' : formatBytes(data.photosBytes),
                  hint: data == null ? null : '${data.photosFileCount} file${data.photosFileCount == 1 ? '' : 's'}',
                ),
                _StatCard(
                  label: 'Free space',
                  // `null` is unknown, never zero — rendering it as "0 B" would
                  // report a full disk on every platform whose `df` we cannot parse.
                  value: data == null ? '—' : formatOptionalBytes(data.freeDiskBytes),
                  hint: 'Available on the volume holding the data directory',
                ),
              ]),
              div(classes: 'dashboard-row dashboard-row--split', [
                div(classes: 'dashboard-panel dashboard-panel--wide', [
                  p(classes: 'dashboard-panel-title', [.text('Database files')]),
                  if (loading)
                    div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
                  else
                    div(classes: 'maintenance-files', [
                      for (final file in data?.databases ?? const <StorageDatabaseFile>[]) _DatabaseFileRow(file: file),
                    ]),
                ]),
                div(classes: 'dashboard-panel dashboard-panel--tables', [
                  p(classes: 'dashboard-panel-title', [.text('Internal tables')]),
                  if (loading)
                    div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
                  else
                    div(classes: 'maintenance-tables', [
                      for (final table in data?.tables ?? const <StorageTableRows>[])
                        div(classes: 'maintenance-table-row', [
                          span(classes: 'maintenance-table-name', [.text(table.table)]),
                          span(classes: 'maintenance-table-count', [
                            .text(table.rowCount == null ? kUnknownSize : _fmtNum(table.rowCount!)),
                          ]),
                        ]),
                    ]),
                ]),
              ]),
            ],
            if (isClient) ...[
              p(classes: 'maintenance-section-label', [.text('Cleanup')]),
              _CleanupSection(
                logDatabaseName: _logDatabaseFile(data)?.name ?? 'zonai_log.sqlite',
                logDatabaseBytes: _logDatabaseFile(data)?.sizeBytes,
              ),
            ],
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
      if (context.binding.isClient) const ToastOverlay(),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    ...HomeSidebar.styles,
    ...HomeSettingsOverlay.styles,
    ...ToastOverlay.styles,
    css('.maintenance-section-label').styles(
      margin: .zero,
      fontSize: 0.6875.rem,
      fontWeight: .w600,
      letterSpacing: 0.04.rem,
      textTransform: .upperCase,
      color: mutedColor,
    ),
    css(
      '.maintenance-files',
    ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s5)),
    css('.maintenance-file', [
      css('&').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s3),
        padding: .all(ZonaiSpacing.s6),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
      ),
      css('.maintenance-file-header').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .baseline,
        justifyContent: .spaceBetween,
        gap: Gap.all(ZonaiSpacing.s4),
      ),
      css('.maintenance-file-name').styles(fontSize: 0.8125.rem, fontWeight: .w600, color: fgColor),
      css('.maintenance-file-size').styles(fontSize: 0.8125.rem, fontWeight: .w600, color: fgColor),
      css('.maintenance-file-meta').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        flexWrap: .wrap,
        gap: Gap.all(ZonaiSpacing.s5),
        fontSize: 0.75.rem,
        color: mutedColor,
      ),
      // The dead half of the file, called out rather than folded into the
      // total: it is the number that says a rewrite would help.
      css('.maintenance-file-reclaimable').styles(fontWeight: .w600),
    ]),
    css('.maintenance-tables').styles(
      display: .flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(ZonaiSpacing.s1),
      minHeight: .zero,
      overflow: Overflow.auto,
    ),
    css('.maintenance-table-row').styles(
      display: .flex,
      flexDirection: FlexDirection.row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: Gap.all(ZonaiSpacing.s4),
      padding: .symmetric(vertical: ZonaiSpacing.s3, horizontal: ZonaiSpacing.s2),
      fontSize: 0.8125.rem,
    ),
    css('.maintenance-table-name').styles(color: fgColor, raw: const {'font-family': 'var(--zonai-mono, monospace)'}),
    css('.maintenance-table-count').styles(color: mutedColor, fontWeight: .w600),
    css('.maintenance-cleanup').styles(
      display: .grid,
      gap: Gap.all(ZonaiSpacing.s5),
      raw: const {'grid-template-columns': 'repeat(auto-fit, minmax(280px, 1fr))'},
    ),
    css('.maintenance-cleanup-card', [
      css('&').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s4),
        padding: .all(ZonaiSpacing.s6),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
      ),
      css('.maintenance-cleanup-title').styles(margin: .zero, fontSize: 0.8125.rem, fontWeight: .w600, color: fgColor),
      css('.maintenance-cleanup-desc').styles(margin: .zero, fontSize: 0.75.rem, color: mutedColor),
      css(
        '.maintenance-cleanup-control',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2)),
      css('.maintenance-cleanup-label').styles(fontSize: 0.75.rem, fontWeight: .w600, color: fgColor),
      css('.maintenance-cleanup-invalid').styles(fontSize: 0.6875.rem, raw: const {'color': 'var(--zonai-error)'}),
      css('.maintenance-cleanup-actions').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        justifyContent: .end,
        // Pushes the button to the bottom of the card, so a row of cards with
        // descriptions of different lengths still has its buttons in line.
        margin: .only(top: .auto),
      ),
      // The outcome, not a checkmark: this line is the whole reason the
      // endpoints return counts rather than 204s.
      css('.maintenance-cleanup-outcome').styles(margin: .zero, fontSize: 0.75.rem, color: fgColor),
      // A skip is neither success nor failure -- it is the case where the
      // operator has to go and do something about the disk.
      css('.maintenance-cleanup-outcome--skip').styles(fontWeight: .w600, raw: const {'color': 'var(--zonai-error)'}),
    ]),
    css('.maintenance-cleanup-note').styles(margin: .zero, fontSize: 0.75.rem, color: mutedColor),
  ];
}

/// One database file: what it occupies, and how much of that is dead.
class _DatabaseFileRow extends StatelessComponent {
  const _DatabaseFileRow({required this.file});

  final StorageDatabaseFile file;

  @override
  Component build(BuildContext context) {
    return div(classes: 'maintenance-file', [
      div(classes: 'maintenance-file-header', [
        span(classes: 'maintenance-file-name', [.text(file.name)]),
        span(classes: 'maintenance-file-size', [.text(formatBytes(file.sizeBytes))]),
      ]),
      div(classes: 'maintenance-file-meta', [
        // Unknown reclaimable renders as a word, not as zero: a freelist that
        // could not be read and a freelist with nothing on it are opposite
        // answers, and only one of them means "no space to recover here".
        span(classes: 'maintenance-file-reclaimable', [
          .text('${formatOptionalBytes(file.reclaimableBytes)} reclaimable'),
        ]),
        if (file.walBytes > 0) span([.text('${formatBytes(file.walBytes)} WAL')]),
        if (file.capBytes case final cap?)
          span([.text('${formatBytes((cap - file.sizeBytes).clamp(0, cap))} under the ${formatBytes(cap)} cap')]),
      ]),
    ]);
  }
}

class _StatCard extends StatelessComponent {
  const _StatCard({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Component build(BuildContext context) {
    return div(classes: 'dashboard-stat-card', events: hint == null ? null : appTooltipEvents(context, text: hint!), [
      span(classes: 'dashboard-stat-label', [.text(label)]),
      span(classes: 'dashboard-stat-value', [.text(value)]),
    ]);
  }
}

/// The log database as the storage report describes it, or `null` before the
/// report arrives.
///
/// Read from the report rather than hardcoded so the reclaim card names — and
/// sizes — the file it will actually lock on this deployment.
StorageDatabaseFile? _logDatabaseFile(StorageMetrics? data) {
  for (final db in data?.databases ?? const <StorageDatabaseFile>[]) {
    if (db.name.contains('log')) return db;
  }
  return null;
}

/// The destructive half of the Maintenance screen.
///
/// Every action here wraps a verb the engine already has; what this adds is a
/// typed confirmation and an honest report of what happened. "Done" is not an
/// outcome — a purge that removed four million rows and one that matched
/// nothing both finish successfully, and only the number tells them apart.
class _CleanupSection extends StatefulComponent {
  const _CleanupSection({required this.logDatabaseName, this.logDatabaseBytes});

  final String logDatabaseName;

  /// Size of the file the reclaim locks, or `null` before the storage report
  /// arrives.
  ///
  /// The stall this action causes scales with it, and "locks a 20 KB file" and
  /// "locks a 3 GB file" are the same sentence describing opposite decisions.
  final int? logDatabaseBytes;

  @override
  State<_CleanupSection> createState() => _CleanupSectionState();
}

class _CleanupSectionState extends State<_CleanupSection> {
  /// Default cutoff for the log purge. A number rather than "everything", so
  /// the least destructive reading of the button is the one it starts on.
  String _days = '30';

  /// Which internal table the purge dropdown is pointing at.
  ///
  /// `_photos` cannot appear here — [kPurgeableTableNames] excludes it, and
  /// the server refuses it independently.
  String _table = _purgeableTables.first;

  /// Typed confirmations, one per action, cleared when the action runs.
  final Map<CleanupAction, String> _confirms = {};

  /// The dropdown's options, sorted so the list is stable between renders.
  static final List<String> _purgeableTables = purgeableTableOptions();

  int? get _parsedDays {
    final trimmed = _days.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  void _clearConfirm(CleanupAction action) {
    setState(() => _confirms.remove(action));
  }

  @override
  Component build(BuildContext context) {
    final state = context.watch(cleanupActionsProvider);

    final days = _parsedDays;
    // An empty box means "every row", which is a real request. A box with
    // something unparseable or negative in it is not, and must not silently
    // become one.
    final daysValid = _days.trim().isEmpty || (days != null && days >= 0);

    return div(classes: 'maintenance-cleanup', [
      _CleanupCard(
        title: 'Reclaim log space',
        // Lock first, and sized -- see [describeReclaimLock], which owns the
        // wording so it can be tested. Safe from data loss precisely because
        // the log database is a file of its own; that is why it was split out.
        description: describeReclaimLock(file: component.logDatabaseName, bytes: component.logDatabaseBytes),
        action: CleanupAction.reclaimLogSpace,
        state: state,
        // Not destructive: it moves no rows, it only rewrites the file around
        // the ones that are left. The lock warning is the disclosure that
        // matters, and a typed confirm on a non-destructive verb would train
        // an operator to type through the ones that are.
        confirmPhrase: null,
        confirmValue: null,
        onConfirmInput: null,
        onRun: () => context.read(cleanupActionsProvider.notifier).reclaimLogSpace(),
        children: const [],
      ),
      _CleanupCard(
        title: 'Purge logs',
        description:
            'Deletes rows from the log table. Leave the box empty to delete every row. '
            'Space is returned to the disk by the reclaim above, not by this.',
        action: CleanupAction.purgeLogs,
        state: state,
        confirmPhrase: 'purge logs',
        confirmValue: _confirms[CleanupAction.purgeLogs] ?? '',
        onConfirmInput: (value) => setState(() => _confirms[CleanupAction.purgeLogs] = value),
        runEnabled: daysValid,
        onRun: () {
          _clearConfirm(CleanupAction.purgeLogs);
          context.read(cleanupActionsProvider.notifier).purgeLogs(olderThanDays: days);
        },
        children: [
          div(classes: 'maintenance-cleanup-control', [
            ZonaiTextField(
              id: 'maintenance-purge-logs-days',
              fieldLabel: 'Older than (days)',
              value: _days,
              placeholder: 'empty = every row',
              onInput: (value) => setState(() => _days = value),
            ),
            if (!daysValid)
              span(classes: 'maintenance-cleanup-invalid', [
                .text('Enter a whole number of days, or leave it empty to delete every row.'),
              ]),
          ]),
        ],
      ),
      _CleanupCard(
        title: 'Purge an internal table',
        description:
            'Empties one of the framework\'s own tables. Application tables are not listed and '
            'are refused by the server.',
        action: CleanupAction.purgeTable,
        state: state,
        // The table's own name is the confirmation. Typing "_jwt" to empty
        // `_jwt` is the one phrase that cannot be muscle-memoried across
        // different tables.
        confirmPhrase: _table,
        confirmValue: _confirms[CleanupAction.purgeTable] ?? '',
        onConfirmInput: (value) => setState(() => _confirms[CleanupAction.purgeTable] = value),
        onRun: () {
          _clearConfirm(CleanupAction.purgeTable);
          context.read(cleanupActionsProvider.notifier).purgeTable(table: _table);
        },
        children: [
          div(classes: 'maintenance-cleanup-control', [
            label(
              id: 'maintenance-purge-table-label',
              classes: 'maintenance-cleanup-label',
              htmlFor: 'maintenance-purge-table',
              [.text('Table')],
            ),
            ZonaiSelect(
              id: 'maintenance-purge-table',
              labelId: 'maintenance-purge-table-label',
              value: _table,
              options: [for (final table in _purgeableTables) ZonaiSelectOption(value: table, label: table)],
              // Changing the target invalidates whatever was typed to confirm
              // the old one -- otherwise "_jwt" typed for `_jwt` would still
              // be sitting there authorising a purge of `_log`.
              onChange: (value) => setState(() {
                _table = value;
                _confirms.remove(CleanupAction.purgeTable);
              }),
            ),
          ]),
        ],
      ),
      _CleanupCard(
        title: 'Delete unreferenced photos',
        // Says out loud why this is not the purge above it.
        description:
            'Deletes photo rows nothing references, and the file behind each one. Photos are not '
            'in the purge list because a bulk delete would remove the rows and orphan their files.',
        action: CleanupAction.cleanupPhotos,
        state: state,
        confirmPhrase: 'delete photos',
        confirmValue: _confirms[CleanupAction.cleanupPhotos] ?? '',
        onConfirmInput: (value) => setState(() => _confirms[CleanupAction.cleanupPhotos] = value),
        onRun: () {
          _clearConfirm(CleanupAction.cleanupPhotos);
          context.read(cleanupActionsProvider.notifier).cleanupPhotos();
        },
        children: const [],
      ),
      // The remaining cleanup verbs already have Run buttons on the dashboard
      // and are registered crons, so pointing at them beats duplicating them.
      p(classes: 'maintenance-cleanup-note', [
        .text(
          'Expired JWTs and old rate-limit rows are cleaned by the _delete_expired_jwts and '
          '_delete_old_rate_limits cron jobs, which can be run on demand from the Cron Jobs '
          'panel on the dashboard.',
        ),
      ]),
    ]);
  }
}

/// One cleanup verb: what it does, what it needs typed, and what it did.
class _CleanupCard extends StatelessComponent {
  const _CleanupCard({
    required this.title,
    required this.description,
    required this.action,
    required this.state,
    required this.confirmPhrase,
    required this.confirmValue,
    required this.onConfirmInput,
    required this.onRun,
    required this.children,
    this.runEnabled = true,
  });

  final String title;
  final String description;
  final CleanupAction action;
  final CleanupActionsState state;

  /// What the operator must type to arm the button, or `null` for a verb that
  /// needs no confirmation.
  final String? confirmPhrase;
  final String? confirmValue;
  final void Function(String value)? onConfirmInput;
  final void Function() onRun;
  final List<Component> children;
  final bool runEnabled;

  @override
  Component build(BuildContext context) {
    final isRunning = state.running == action;
    final confirmed =
        confirmPhrase == null || cleanupConfirmMatches(typed: confirmValue ?? '', expected: confirmPhrase!);

    // Disabled while *any* action runs, not just this one: these all serialize
    // against writes in the engine, so a second click only queues a wait.
    final disabled = state.isBusy || !confirmed || !runEnabled;
    final outcome = state.outcomes[action];

    return div(classes: 'maintenance-cleanup-card', [
      p(classes: 'maintenance-cleanup-title', [.text(title)]),
      p(classes: 'maintenance-cleanup-desc', [.text(description)]),
      ...children,
      if (confirmPhrase case final phrase?)
        div(classes: 'maintenance-cleanup-control', [
          ZonaiTextField(
            id: 'maintenance-confirm-${action.name}',
            fieldLabel: 'Type "$phrase" to confirm',
            value: confirmValue ?? '',
            placeholder: phrase,
            onInput: onConfirmInput ?? (_) {},
            attributes: const {'autocapitalize': 'none', 'spellcheck': 'false'},
          ),
        ]),
      div(classes: 'maintenance-cleanup-actions', [
        ZonaiButton(
          variant: ZonaiButtonVariant.secondary,
          size: ZonaiButtonSize.sm,
          disabled: disabled,
          onClick: disabled ? null : onRun,
          child: .text(isRunning ? 'Running...' : 'Run'),
        ),
      ]),
      if (outcome != null)
        p(
          classes:
              'maintenance-cleanup-outcome'
              '${outcome.isSkip ? ' maintenance-cleanup-outcome--skip' : ''}',
          // A skip is not a failure and not a success, so it is announced
          // rather than left for a sighted reader to notice the colour of.
          attributes: {'role': 'status'},
          [.text(outcome.text)],
        ),
    ]);
  }
}

String _fmtNum(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
