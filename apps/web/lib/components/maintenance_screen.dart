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
import 'theme/zonai_icon_button.dart';
import 'toast_overlay.dart';

/// Operator screen for "how much space is zonai using, and how much is left".
///
/// Separate from the dashboard for two reasons that point the same way: the
/// dashboard is read-only by contract, and collecting storage is expensive
/// enough that it must not ride the dashboard's metrics poll.
///
/// The destructive cleanup tools belong on this screen too, below the storage
/// section — they are a sibling change, not part of this one.
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
                      : appTooltipEvents(
                          context,
                          text: 'Refresh storage',
                          placement: AppTooltipPlacement.belowLeft,
                        ),
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
                      for (final file in data?.databases ?? const <StorageDatabaseFile>[])
                        _DatabaseFileRow(file: file),
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
    css('.maintenance-files').styles(
      display: .flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(ZonaiSpacing.s5),
    ),
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
    return div(
      classes: 'dashboard-stat-card',
      events: hint == null ? null : appTooltipEvents(context, text: hint!),
      [
        span(classes: 'dashboard-stat-label', [.text(label)]),
        span(classes: 'dashboard-stat-value', [.text(value)]),
      ],
    );
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
