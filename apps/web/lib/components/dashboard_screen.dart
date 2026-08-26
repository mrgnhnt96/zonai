import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
// `show`: payloads.dart also exports a `DashboardMetrics`, and this file means
// the provider's one.
import 'package:zonai_schema/payloads.dart' show DashboardDrainRun, DashboardPushQueue, DashboardSessions, formatBytes;

import '../auth/auth_routes.dart';
import '../constants/button_sizes.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/dashboard_provider.dart';
import '../providers/maintenance_provider.dart';
import '../utils/cron_job_summary.dart';
import '../providers/app_tooltip_provider.dart';
import '../providers/home_ui_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../utils/sqlite_table_utils.dart';
import 'app_tooltip_overlay.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/zonai_button.dart';
import 'theme/zonai_icon_button.dart';
import 'toast_overlay.dart';

class DashboardScreen extends StatelessComponent {
  const DashboardScreen({super.key});

  @override
  Component build(BuildContext context) {
    final mobileNavOpen = context.watch(homeUiProvider).mobileNavOpen;
    final tables = context.watch(sqliteTablesProvider);
    final userTables = [
      for (final t in tables.tables)
        if (!isSystemSqliteTable(t.sqliteName)) t,
    ];

    final excludeAdmin = context.watch(excludeAdminProvider);

    // Async providers must not notify after SSR completes (no frames on the server).
    final isClient = context.binding.isClient;
    final metrics = isClient ? context.watch(dashboardMetricsProvider) : const AsyncValue<DashboardMetrics>.loading();
    final topErrors = isClient ? context.watch(topErrorsProvider) : const AsyncValue<List<TopError>>.loading();
    final expandedError = context.watch(expandedErrorProvider);
    final cronJobs = isClient ? context.watch(cronJobsProvider) : const AsyncValue<List<CronJobSummary>>.loading();
    final cronJobsData = cronJobs.value ?? [];
    final cronJobsLoading = cronJobs.isLoading;
    final runningCronJobs = isClient ? context.watch(runningCronJobsProvider) : const <String>{};
    final tableCounts = isClient ? context.watch(tableCountsProvider) : const AsyncValue<Map<String, int>>.loading();

    final statsData = metrics.value?.stats;
    final bucketsData = metrics.value?.buckets ?? [];
    final topErrorsData = topErrors.value ?? [];
    final tableCountsData = tableCounts.value ?? {};

    final maxBucket = bucketsData.isEmpty ? 0 : bucketsData.map((bkt) => bkt.count).reduce((x, y) => x > y ? x : y);

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
          h1(classes: 'home-mobile-nav-title', [.text('Dashboard')]),
        ]),
        div(classes: 'dashboard-scroller', [
          div(classes: 'dashboard', [
            div(classes: 'dashboard-header', [
              h1(classes: 'dashboard-title', [.text('Dashboard')]),
              label(
                classes: 'dashboard-filter-label',
                events: appTooltipEvents(
                  context,
                  text: 'Excludes admin requests and errors\nfrom stats, charts, and top errors',
                  placement: AppTooltipPlacement.belowLeft,
                ),
                [
                  input<bool>(
                    type: InputType.checkbox,
                    classes: 'dashboard-filter-checkbox',
                    checked: excludeAdmin,
                    onChange: (_) => context.read(excludeAdminProvider.notifier).toggle(),
                  ),
                  .text('Exclude admin'),
                ],
              ),
            ]),
            // Stat cards. Active sessions is deliberately not here any more —
            // it lives in the Sessions panel next to the distinct-user count
            // that gives it meaning.
            div(classes: 'dashboard-stats', [
              _StatCard(label: 'Requests (24h)', value: statsData != null ? _fmtNum(statsData.requestCount24h) : '—'),
              _StatCard(label: 'Error Rate', value: statsData != null ? _fmtPercent(statsData.errorRate) : '—'),
              _StatCard(label: 'p95 Response', value: statsData != null ? _fmtMs(statsData.p95ResponseMs) : '—'),
            ]),
            // Storage at a glance, linking to the Maintenance screen that
            // breaks it down. Deliberately three numbers and a link: the
            // collection behind them is expensive, and the dashboard is
            // read-only by contract.
            const _StorageStrip(),
            // Requests graph + Top errors
            div(classes: 'dashboard-row', [
              div(classes: 'dashboard-panel dashboard-panel--wide', [
                p(classes: 'dashboard-panel-title', [.text('Requests over time')]),
                if (bucketsData.isEmpty)
                  div(classes: 'dashboard-panel-placeholder', [.text('Loading...')])
                else
                  div(classes: 'dashboard-chart-wrap', [
                    div(classes: 'dashboard-chart', [
                      for (final bucket in bucketsData)
                        div(
                          classes: 'dashboard-chart-bar${bucket.count == 0 ? ' dashboard-chart-bar--empty' : ''}',
                          attributes: {
                            'style':
                                'height: ${maxBucket == 0 ? 2 : (bucket.count / maxBucket * 100).round().clamp(2, 100)}%',
                            'data-tip': '${_fmtHour(bucket.hour)}: ${bucket.count}',
                          },
                          [],
                        ),
                    ]),
                    div(classes: 'dashboard-chart-labels', [
                      for (var i = 0; i < bucketsData.length; i += 6)
                        span(classes: 'dashboard-chart-label', [.text(_fmtHour(bucketsData[i].hour))]),
                      span(classes: 'dashboard-chart-label', [.text(_fmtHour(bucketsData.last.hour))]),
                    ]),
                  ]),
              ]),
              div(classes: 'dashboard-panel dashboard-panel--errors', [
                p(classes: 'dashboard-panel-title', [.text('Top Errors (24h)')]),
                if (topErrors.isLoading && !topErrors.hasValue)
                  div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
                else if (topErrorsData.isEmpty)
                  div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
                    .text('No errors in the last 24h'),
                  ])
                else
                  div(classes: 'dashboard-error-list', [
                    for (final err in topErrorsData)
                      div(
                        classes:
                            'dashboard-error-item${expandedError == err.message ? ' dashboard-error-item--expanded' : ''}',
                        events: {'click': (_) => context.read(expandedErrorProvider.notifier).toggle(err.message)},
                        [
                          div(classes: 'dashboard-error-header', [
                            span(classes: 'dashboard-error-msg', [.text(err.message)]),
                            div(classes: 'dashboard-error-footer', [
                              span(classes: 'dashboard-error-count', [.text('${err.count}×')]),
                              span(classes: 'dashboard-error-time', [.text(_timeAgo(err.lastSeen))]),
                            ]),
                          ]),
                          if (expandedError == err.message)
                            pre(classes: 'dashboard-error-detail', [.text(err.detail ?? err.message)]),
                        ],
                      ),
                  ]),
              ]),
            ]),
            // Push queue + sessions. Both read-only: the dashboard's contract
            // is look-don't-touch, and draining is already reachable through
            // the Run button on `_drain_push_jobs` in the Cron Jobs panel
            // below.
            div(classes: 'dashboard-row dashboard-row--split', [
              _PushQueuePanel(queue: metrics.value?.pushQueue, isLoading: metrics.isLoading && !metrics.hasValue),
              _SessionsPanel(sessions: metrics.value?.sessions, isLoading: metrics.isLoading && !metrics.hasValue),
            ]),
            div(classes: 'dashboard-row dashboard-row--split', [
              div(classes: 'dashboard-panel dashboard-panel--crons', [
                div(classes: 'dashboard-panel-heading', [
                  p(classes: 'dashboard-panel-title', [
                    .text(cronJobsData.isEmpty ? 'Cron Jobs' : 'Cron Jobs (${cronJobsData.length})'),
                  ]),
                  if (isClient)
                    ZonaiIconButton(
                      size: ZonaiIconButtonSize.xs,
                      variant: ZonaiIconButtonVariant.ghost,
                      disabled: cronJobsLoading,
                      attributes: {'aria-label': 'Refresh cron jobs'},
                      events: cronJobsLoading
                          ? null
                          : appTooltipEvents(
                              context,
                              text: 'Refresh cron jobs',
                              placement: AppTooltipPlacement.belowLeft,
                            ),
                      onClick: () => context.read(cronJobsProvider.notifier).refresh(),
                      child: _dashboardRefreshIcon(),
                    ),
                ]),
                if (cronJobsLoading && cronJobsData.isEmpty)
                  div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
                else if (cronJobsData.isEmpty)
                  div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
                    .text('No cron jobs found'),
                  ])
                else
                  div(classes: 'dashboard-cron-list', [
                    for (final job in cronJobsData)
                      _CronJobRow(
                        job: job,
                        isSubmitting: runningCronJobs.contains(job.name),
                        showRun: isClient,
                        onRun: () => context.read(runningCronJobsProvider.notifier).run(job.name),
                      ),
                  ]),
              ]),
              if (userTables.isNotEmpty)
                div(classes: 'dashboard-panel dashboard-panel--tables', [
                  p(classes: 'dashboard-panel-title', [.text('Tables')]),
                  div(classes: 'dashboard-tables', [
                    for (final table in userTables)
                      a(
                        href: AuthRoutes.toUrlPath(AuthRoutes.forTable(table.sqliteName)),
                        classes: 'dashboard-table-card',
                        [
                          span(classes: 'dashboard-table-name', [.text(table.displayName)]),
                          span(classes: 'dashboard-table-meta', [
                            .text(_fmtTableMeta(tableCountsData[table.sqliteName])),
                          ]),
                        ],
                      ),
                  ]),
                ]),
            ]),
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
    css('.dashboard-scroller').styles(
      flex: Flex(grow: 1, shrink: 1),
      display: .flex,
      flexDirection: FlexDirection.column,
      alignItems: .center,
      minHeight: .zero,
      overflow: Overflow.auto,
      // Bleed back out over `.home-main`'s right padding (also ZonaiSpacing.s10)
      // so the scrollbar sits flush against the viewport edge; the matching
      // padding leaves the content inset exactly where it was.
      margin: .only(right: Unit.expression('-${ZonaiSpacing.s10.value}')),
      padding: .only(right: ZonaiSpacing.s10),
      raw: const {'-webkit-overflow-scrolling': 'touch'},
    ),
    css('.dashboard', [
      css('&').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s10),
        width: 100.percent,
        maxWidth: 1200.px,
        margin: .symmetric(horizontal: .auto),
      ),
      css(
        '.dashboard-header',
      ).styles(display: .flex, flexDirection: FlexDirection.row, alignItems: .center, justifyContent: .spaceBetween),
      css(
        '.dashboard-title',
      ).styles(margin: .zero, fontSize: 1.375.rem, fontWeight: .w600, raw: const {'letter-spacing': '-0.02em'}),
      css('.dashboard-filter-label').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(ZonaiSpacing.s2),
        fontSize: 0.8125.rem,
        fontWeight: .w500,
        color: mutedColor,
        cursor: .pointer,
        raw: const {'user-select': 'none'},
      ),
      css(
        '.dashboard-filter-checkbox',
      ).styles(raw: const {'accent-color': 'var(--zonai-primary)', 'cursor': 'pointer'}),
      // Stat cards
      css(
        '.dashboard-stats',
      ).styles(display: .flex, flexDirection: FlexDirection.row, flexWrap: .wrap, gap: Gap.all(ZonaiSpacing.s5)),
      css('.dashboard-stat-card').styles(
        flex: Flex(grow: 1, shrink: 0),
        minWidth: 140.px,
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        padding: .all(ZonaiSpacing.s8),
        backgroundColor: surfaceColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        raw: const {'box-shadow': 'var(--zonai-shadow-sm)'},
      ),
      css('.dashboard-stat-label').styles(
        fontSize: 0.6875.rem,
        fontWeight: .w600,
        letterSpacing: 0.04.rem,
        textTransform: .upperCase,
        color: mutedColor,
      ),
      css(
        '.dashboard-stat-value',
      ).styles(fontSize: 1.5.rem, fontWeight: .w600, color: fgColor, raw: const {'letter-spacing': '-0.02em'}),
      // Panels
      css(
        '.dashboard-row',
      ).styles(display: .flex, flexDirection: FlexDirection.row, flexWrap: .wrap, gap: Gap.all(ZonaiSpacing.s5)),
      css('.dashboard-row--split').styles(alignItems: .stretch, flexWrap: .wrap, width: 100.percent),
      css('.dashboard-panel').styles(
        flex: Flex(grow: 1, shrink: 1),
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s6),
        padding: .all(ZonaiSpacing.s8),
        backgroundColor: surfaceColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(12.px)),
        raw: const {'box-shadow': 'var(--zonai-shadow-sm)'},
      ),
      css('.dashboard-panel--wide').styles(flex: Flex(grow: 2, shrink: 1), minWidth: 320.px),
      css('.dashboard-panel--errors').styles(flex: Flex(grow: 1, shrink: 1), maxWidth: 400.px, minWidth: 240.px),
      css('.dashboard-panel--crons').styles(
        flex: Flex(grow: 1, shrink: 1),
        maxWidth: 100.percent,
        minWidth: .zero,
        minHeight: .zero,
        raw: const {'flex-basis': '420px'},
      ),
      css(
        '.dashboard-panel--tables',
      ).styles(flex: Flex(grow: 999, shrink: 1), minWidth: 280.px, minHeight: .zero, raw: const {'flex-basis': '0'}),
      css(
        '.dashboard-panel-heading',
      ).styles(display: .flex, flexDirection: FlexDirection.row, alignItems: .center, justifyContent: .spaceBetween),
      css('.dashboard-refresh-icon').styles(width: 1.em, height: 1.em, display: .block),
      // Compact storage strip, linking to the Maintenance screen.
      css('.dashboard-storage-strip', [
        css('&').styles(
          display: .flex,
          flexDirection: FlexDirection.row,
          flexWrap: .wrap,
          alignItems: .center,
          gap: Gap.all(ZonaiSpacing.s6),
          padding: .symmetric(vertical: ZonaiSpacing.s5, horizontal: ZonaiSpacing.s8),
          backgroundColor: surfaceColor,
          border: .all(color: borderColor, width: 1.px, style: .solid),
          radius: .all(Radius.circular(12.px)),
          fontSize: 0.8125.rem,
          color: mutedColor,
          textDecoration: const TextDecoration(line: TextDecorationLine.none),
        ),
        css('&:hover').styles(
          border: .all(color: primaryColor, width: 1.px, style: .solid),
        ),
        css(
          '.dashboard-storage-strip-label',
        ).styles(fontSize: 0.6875.rem, fontWeight: .w600, letterSpacing: 0.04.rem, textTransform: .upperCase),
        css('.dashboard-storage-strip-value').styles(color: fgColor, fontWeight: .w600),
        css('.dashboard-storage-strip-more').styles(
          margin: .only(left: .auto),
          color: primaryColor,
          fontWeight: .w600,
        ),
      ]),
      // Push queue panel
      css(
        '.dashboard-panel--push',
      ).styles(flex: Flex(grow: 1, shrink: 1), minWidth: .zero, minHeight: .zero, raw: const {'flex-basis': '420px'}),
      css('.dashboard-push-outstanding').styles(
        fontSize: 0.6875.rem,
        fontWeight: .w600,
        color: fgColor,
        padding: .symmetric(vertical: 2.px, horizontal: ZonaiSpacing.s3),
        radius: .all(Radius.circular(999.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        raw: const {'cursor': 'default'},
      ),
      css('.dashboard-push-outstanding--idle').styles(color: mutedColor),
      css(
        '.dashboard-push-depth',
      ).styles(display: .flex, flexDirection: FlexDirection.row, flexWrap: .wrap, gap: Gap.all(ZonaiSpacing.s3)),
      css('.dashboard-push-depth-cell').styles(
        flex: Flex(grow: 1, shrink: 1),
        minWidth: 72.px,
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s1),
        padding: .symmetric(vertical: ZonaiSpacing.s3, horizontal: ZonaiSpacing.s4),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        raw: const {'border-left-width': '3px'},
      ),
      css('.dashboard-push-depth-cell--pending').styles(raw: const {'border-left-color': 'var(--zonai-border)'}),
      css('.dashboard-push-depth-cell--running').styles(raw: const {'border-left-color': 'var(--zonai-muted)'}),
      css('.dashboard-push-depth-cell--ok').styles(raw: const {'border-left-color': 'var(--zonai-success)'}),
      css('.dashboard-push-depth-cell--failed').styles(raw: const {'border-left-color': 'var(--zonai-error)'}),
      css(
        '.dashboard-push-depth-value',
      ).styles(fontSize: 1.125.rem, fontWeight: .w600, color: fgColor, raw: const {'letter-spacing': '-0.02em'}),
      css(
        '.dashboard-push-note',
      ).styles(margin: .zero, fontSize: 0.6875.rem, color: mutedColor, raw: const {'cursor': 'default'}),
      css('.dashboard-push-drain').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(ZonaiSpacing.s3),
        fontSize: 0.75.rem,
      ),
      css('.dashboard-push-drain-label').styles(
        fontSize: 0.6875.rem,
        fontWeight: .w600,
        letterSpacing: 0.04.rem,
        textTransform: .upperCase,
        color: mutedColor,
      ),
      css('.dashboard-push-drain-value').styles(color: fgColor, fontWeight: .w500),
      css('.dashboard-push-subtitle').styles(
        margin: .zero,
        fontSize: 0.6875.rem,
        fontWeight: .w600,
        letterSpacing: 0.04.rem,
        textTransform: .upperCase,
        color: mutedColor,
      ),
      css('.dashboard-push-failures').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        minHeight: .zero,
        maxHeight: 220.px,
        overflow: Overflow.auto,
      ),
      css(
        '.dashboard-push-failure',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2), minWidth: .zero),
      css('.dashboard-push-failure-id').styles(
        fontSize: 0.6875.rem,
        color: mutedColor,
        raw: const {'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'},
      ),
      css('.dashboard-push-failure-count').styles(fontSize: 0.6875.rem, fontWeight: .w600, color: fgColor),
      // Sessions panel
      css(
        '.dashboard-panel--sessions',
      ).styles(flex: Flex(grow: 1, shrink: 1), minWidth: .zero, minHeight: .zero, raw: const {'flex-basis': '320px'}),
      css(
        '.dashboard-session-figures',
      ).styles(display: .flex, flexDirection: FlexDirection.row, flexWrap: .wrap, gap: Gap.all(ZonaiSpacing.s3)),
      css('.dashboard-session-figure').styles(
        flex: Flex(grow: 1, shrink: 1),
        minWidth: 84.px,
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s1),
        padding: .symmetric(vertical: ZonaiSpacing.s3, horizontal: ZonaiSpacing.s4),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        raw: const {'cursor': 'default'},
      ),
      css(
        '.dashboard-session-figure-value',
      ).styles(fontSize: 1.125.rem, fontWeight: .w600, color: fgColor, raw: const {'letter-spacing': '-0.02em'}),
      css('.dashboard-session-users').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        minHeight: .zero,
        maxHeight: 200.px,
        overflow: Overflow.auto,
      ),
      css('.dashboard-session-user').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(ZonaiSpacing.s3),
        padding: .symmetric(vertical: ZonaiSpacing.s2, horizontal: ZonaiSpacing.s4),
        radius: .all(Radius.circular(6.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        minWidth: .zero,
      ),
      css(
        '.dashboard-session-user-count',
      ).styles(fontSize: 0.6875.rem, color: mutedColor, raw: const {'flex': '0 0 auto'}),
      css('.dashboard-panel-title').styles(margin: .zero, fontSize: 0.875.rem, fontWeight: .w600, color: fgColor),
      css('.dashboard-panel-placeholder').styles(
        flex: Flex(grow: 1, shrink: 0),
        minHeight: 140.px,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        fontSize: 0.875.rem,
        color: mutedColor,
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        raw: const {'border-style': 'dashed'},
      ),
      css('.dashboard-panel-placeholder--sm').styles(minHeight: 72.px),
      // Bar chart
      css('.dashboard-chart-wrap').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        flex: Flex(grow: 1, shrink: 0),
      ),
      css('.dashboard-chart').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .end,
        gap: Gap.all(2.px),
        height: 100.px,
        padding: .symmetric(horizontal: ZonaiSpacing.s2),
      ),
      css('.dashboard-chart-bar').styles(
        flex: Flex(grow: 1, shrink: 0),
        backgroundColor: primaryColor,
        radius: .only(topLeft: Radius.circular(2.px), topRight: Radius.circular(2.px)),
        raw: const {
          'position': 'relative',
          'opacity': '0.75',
          'cursor': 'default',
          'transition': 'opacity 0.1s ease',
          'min-height': '2px',
        },
      ),
      css('.dashboard-chart-bar::after').styles(
        raw: const {
          'content': 'attr(data-tip)',
          'position': 'absolute',
          'bottom': 'calc(100% + 6px)',
          'left': '50%',
          'transform': 'translateX(-50%)',
          'padding': '3px 7px',
          'background': 'var(--zonai-fg)',
          'color': 'var(--zonai-bg)',
          'font-size': '0.6875rem',
          'font-weight': '600',
          'white-space': 'nowrap',
          'border-radius': '4px',
          'pointer-events': 'none',
          'opacity': '0',
          'transition': 'opacity 0.1s ease',
          'z-index': '10',
        },
      ),
      css('.dashboard-chart-bar:hover').styles(raw: const {'opacity': '1'}),
      css('.dashboard-chart-bar:hover::after').styles(raw: const {'opacity': '1'}),
      css('.dashboard-chart-bar--empty').styles(backgroundColor: borderColor, raw: const {'opacity': '1'}),
      css('.dashboard-chart-labels').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        justifyContent: .spaceBetween,
        padding: .symmetric(horizontal: ZonaiSpacing.s2),
      ),
      css('.dashboard-chart-label').styles(fontSize: 0.6875.rem, color: mutedColor),
      // Error list
      css('.dashboard-error-list').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        flex: Flex(grow: 1, shrink: 1),
        overflow: Overflow.auto,
      ),
      css('.dashboard-error-item').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        padding: .symmetric(vertical: ZonaiSpacing.s3, horizontal: ZonaiSpacing.s4),
        radius: .all(Radius.circular(6.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        cursor: .pointer,
        minWidth: .zero,
        raw: const {'transition': 'border-color 0.15s ease'},
      ),
      css('.dashboard-error-item:hover').styles(
        border: .all(color: mutedColor, width: 1.px, style: .solid),
      ),
      css('.dashboard-error-item--expanded').styles(
        border: .all(color: errorColor, width: 1.px, style: .solid),
      ),
      css('.dashboard-error-item--expanded:hover').styles(
        border: .all(color: errorColor, width: 1.px, style: .solid),
      ),
      css(
        '.dashboard-error-header',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2), minWidth: .zero),
      css('.dashboard-error-detail').styles(
        margin: .zero,
        padding: .all(ZonaiSpacing.s4),
        fontSize: 0.6875.rem,
        color: errorFgColor,
        backgroundColor: errorBgColor,
        radius: .all(Radius.circular(4.px)),
        raw: const {
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
          'white-space': 'pre-wrap',
          'overflow-wrap': 'anywhere',
          'line-height': '1.5',
          'max-height': '200px',
          'overflow-y': 'auto',
        },
      ),
      css('.dashboard-error-msg').styles(
        fontSize: 0.75.rem,
        color: fgColor,
        raw: const {
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
          'white-space': 'normal',
          'overflow-wrap': 'anywhere',
          'line-height': '1.4',
        },
      ),
      css(
        '.dashboard-error-footer',
      ).styles(display: .flex, flexDirection: FlexDirection.row, alignItems: .center, gap: Gap.all(ZonaiSpacing.s4)),
      css('.dashboard-error-count').styles(fontSize: 0.6875.rem, fontWeight: .w600, color: errorColor),
      css('.dashboard-error-time').styles(fontSize: 0.6875.rem, color: mutedColor),
      // Cron list
      css('.dashboard-cron-list').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s2),
        flex: Flex(grow: 1, shrink: 1),
        minHeight: .zero,
        maxHeight: 280.px,
        overflow: Overflow.auto,
      ),
      css('.dashboard-cron-item').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(ZonaiSpacing.s3),
        padding: .symmetric(vertical: ZonaiSpacing.s3, horizontal: ZonaiSpacing.s4),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        raw: const {'border-left-width': '3px'},
      ),
      css('.dashboard-cron-item--ok').styles(raw: const {'border-left-color': 'var(--zonai-success)'}),
      css('.dashboard-cron-item--failed').styles(raw: const {'border-left-color': 'var(--zonai-error)'}),
      css('.dashboard-cron-item--running').styles(raw: const {'border-left-color': 'var(--zonai-muted)'}),
      css('.dashboard-cron-item--pending').styles(raw: const {'border-left-color': 'var(--zonai-border)'}),
      css('.dashboard-cron-main').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s1),
        flex: Flex(grow: 1, shrink: 1),
        minWidth: .zero,
      ),
      css('.dashboard-cron-name').styles(
        fontSize: 0.8125.rem,
        fontWeight: .w500,
        color: fgColor,
        raw: const {
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
          'overflow': 'hidden',
          'text-overflow': 'ellipsis',
          'white-space': 'nowrap',
        },
      ),
      css('.dashboard-cron-meta').styles(fontSize: 0.6875.rem, color: mutedColor),
      // Tables
      css('.dashboard-tables').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        flexWrap: .wrap,
        gap: Gap.all(ZonaiSpacing.s4),
        flex: Flex(grow: 1, shrink: 1),
        minHeight: .zero,
        maxHeight: 280.px,
        overflow: Overflow.auto,
        alignContent: .start,
      ),
      css('.dashboard-table-card').styles(
        display: .flex,
        flexDirection: FlexDirection.column,
        gap: Gap.all(ZonaiSpacing.s1),
        padding: .symmetric(horizontal: ZonaiSpacing.s7, vertical: ZonaiSpacing.s6),
        backgroundColor: surfaceColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
        radius: .all(Radius.circular(10.px)),
        minWidth: 140.px,
        raw: const {
          'text-decoration': 'none',
          'box-shadow': 'var(--zonai-shadow-sm)',
          'transition': 'border-color 0.15s ease, background-color 0.15s ease',
        },
      ),
      css('.dashboard-table-card:hover').styles(
        backgroundColor: hoverColor,
        border: .all(color: mutedColor, width: 1.px, style: .solid),
      ),
      css('.dashboard-table-name').styles(fontSize: 0.875.rem, fontWeight: .w600, color: fgColor),
      css('.dashboard-table-meta').styles(fontSize: 0.75.rem, color: mutedColor),
      css.media(MediaQuery.all(maxWidth: 1024.px), [
        css('.dashboard-panel--wide').styles(flex: Flex(grow: 1, shrink: 1), width: 100.percent, minWidth: 100.percent),
        css(
          '.dashboard-panel--errors',
        ).styles(flex: Flex(grow: 1, shrink: 1), width: 100.percent, maxWidth: 100.percent, minWidth: 100.percent),
      ]),
      css.media(MediaQuery.all(maxWidth: 640.px), [css('.dashboard-header').styles(display: .none)]),
    ]),
  ];
}

/// Total DB / photos / free, linking to the Maintenance screen.
class _StorageStrip extends StatelessComponent {
  const _StorageStrip();

  @override
  Component build(BuildContext context) {
    final isClient = context.binding.isClient;
    final storage = isClient ? context.watch(storageMetricsProvider).value : null;

    return a(href: AuthRoutes.toUrlPath(AuthRoutes.maintenance), classes: 'dashboard-storage-strip', [
      span(classes: 'dashboard-storage-strip-label', [.text('Storage')]),
      span(classes: 'dashboard-storage-strip-value', [
        .text(storage == null ? '—' : formatBytes(storage.totalDatabaseBytes)),
      ]),
      span([.text('databases')]),
      span(classes: 'dashboard-storage-strip-value', [.text(storage == null ? '—' : formatBytes(storage.photosBytes))]),
      span([.text('photos')]),
      // Unknown free space is a word, not a zero — see [formatOptionalBytes].
      span(classes: 'dashboard-storage-strip-value', [
        .text(storage == null ? '—' : formatOptionalBytes(storage.freeDiskBytes)),
      ]),
      span([.text('free')]),
      span(classes: 'dashboard-storage-strip-more', [.text('Maintenance →')]),
    ]);
  }
}

/// The `_push_jobs` queue: depth by status, the last drain, and the failures.
///
/// **What this panel will not say.** It reports no "notifications sent" figure
/// for the last drain, because none is recorded — `DrainPushJobsResponse.sent`
/// goes to the cron and then into `_log` as prose, and no column holds it. The
/// `delivered` number here is a sum over the job rows still retained, which is
/// a different claim and is labelled as one. A count of jobs would say nothing
/// about whether any notification went out, so it is not offered as if it did.
class _PushQueuePanel extends StatelessComponent {
  const _PushQueuePanel({required this.queue, required this.isLoading});

  final DashboardPushQueue? queue;
  final bool isLoading;

  @override
  Component build(BuildContext context) {
    final queue = this.queue;

    return div(classes: 'dashboard-panel dashboard-panel--push', [
      div(classes: 'dashboard-panel-heading', [
        p(classes: 'dashboard-panel-title', [.text('Push Queue')]),
        if (queue != null)
          span(
            classes: 'dashboard-push-outstanding${queue.outstanding == 0 ? ' dashboard-push-outstanding--idle' : ''}',
            events: appTooltipEvents(
              context,
              text:
                  'Jobs still to be worked (pending + running).\nFinished jobs are kept for 7 days and not counted here.',
              placement: AppTooltipPlacement.belowLeft,
            ),
            [.text(queue.outstanding == 0 ? 'Idle' : '${_fmtNum(queue.outstanding)} outstanding')],
          ),
      ]),
      if (queue == null)
        div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
          .text(isLoading ? 'Loading...' : 'No data'),
        ])
      else ...[
        div(classes: 'dashboard-push-depth', [
          _PushDepthCell(label: 'Pending', value: queue.pending, tone: 'pending'),
          _PushDepthCell(label: 'Running', value: queue.running, tone: 'running'),
          _PushDepthCell(label: 'Completed', value: queue.completed, tone: 'ok'),
          _PushDepthCell(label: 'Failed', value: queue.failed, tone: 'failed'),
        ]),
        // Recipient counters, not job counters, and said so on the label: a
        // job count cannot answer "did a notification go out" and this can.
        p(
          classes: 'dashboard-push-note',
          events: appTooltipEvents(
            context,
            text:
                'Summed across the job rows still retained.\n_cleanup_push_jobs prunes finished jobs after 7 days,\nso this is a floor on everything ever sent — not a total.',
            placement: AppTooltipPlacement.belowLeft,
          ),
          [
            .text(
              'Recipients reached ${_fmtNum(queue.delivered)} · '
              'rejected ${_fmtNum(queue.permanentlyRejected)} · '
              'retryable ${_fmtNum(queue.transientlyFailed)}',
            ),
          ],
        ),
        div(classes: 'dashboard-push-drain', [
          span(classes: 'dashboard-push-drain-label', [.text('Last drain')]),
          span(classes: 'dashboard-push-drain-value', [.text(_fmtDrain(queue.lastDrain))]),
        ]),
        if (queue.lastDrain?.error case final drainError?) pre(classes: 'dashboard-error-detail', [.text(drainError)]),
        if (queue.failedJobs.isNotEmpty) ...[
          p(classes: 'dashboard-push-subtitle', [
            .text(
              queue.failed > queue.failedJobs.length
                  ? 'Failed jobs (${queue.failedJobs.length} of ${_fmtNum(queue.failed)})'
                  : 'Failed jobs',
            ),
          ]),
          div(classes: 'dashboard-push-failures', [
            for (final job in queue.failedJobs)
              div(classes: 'dashboard-push-failure', [
                div(classes: 'dashboard-error-footer', [
                  span(classes: 'dashboard-push-failure-id', [.text(job.id)]),
                  // Delivered travels with the error: "failed having reached
                  // nobody" is re-sendable and "failed at 40,000 of 50,000" is
                  // not, and the error text alone does not distinguish them.
                  span(classes: 'dashboard-push-failure-count', [.text('${_fmtNum(job.delivered)} reached')]),
                  span(classes: 'dashboard-error-time', [.text(_timeAgo(job.updatedAt))]),
                ]),
                pre(classes: 'dashboard-error-detail', [.text(job.error ?? 'Failed with no reason recorded')]),
              ]),
          ]),
        ],
      ],
    ]);
  }
}

class _PushDepthCell extends StatelessComponent {
  const _PushDepthCell({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final String tone;

  @override
  Component build(BuildContext context) {
    return div(classes: 'dashboard-push-depth-cell dashboard-push-depth-cell--$tone', [
      span(classes: 'dashboard-push-depth-value', [.text(_fmtNum(value))]),
      span(classes: 'dashboard-stat-label', [.text(label)]),
    ]);
  }
}

/// Sessions, from the three columns `_jwt` actually has.
///
/// **What this panel cannot show, and does not pretend to.** `_jwt` is `id`,
/// `user_id` and `expires_at` — there is no `created_at`, no device, no IP and
/// no last-seen. So there is no sessions-over-time chart here, no "signed in
/// from", and no idle-session list; those would need columns the table does not
/// carry.
///
/// There is also no revoke button. Revoking every session for a user is a
/// delete by `user_id`, and the dashboard is read-only by contract — the
/// destructive verbs live on the Maintenance screen.
class _SessionsPanel extends StatelessComponent {
  const _SessionsPanel({required this.sessions, required this.isLoading});

  final DashboardSessions? sessions;
  final bool isLoading;

  @override
  Component build(BuildContext context) {
    final sessions = this.sessions;

    return div(classes: 'dashboard-panel dashboard-panel--sessions', [
      p(classes: 'dashboard-panel-title', [.text('Sessions')]),
      if (sessions == null)
        div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
          .text(isLoading ? 'Loading...' : 'No data'),
        ])
      else if (sessions.active == 0)
        div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Nobody is signed in')])
      else ...[
        div(classes: 'dashboard-session-figures', [
          _SessionFigure(
            label: 'Active',
            value: _fmtNum(sessions.active),
            tip:
                'Sessions whose expiry is still in the future.\n_delete_expired_jwts only sweeps at 04:00, so the row\ncount is higher than this between sweeps.',
          ),
          _SessionFigure(
            label: 'Users',
            value: _fmtNum(sessions.distinctUsers),
            tip: 'Distinct users across those sessions.\nThe gap from Active is the multi-device story.',
          ),
          _SessionFigure(
            label: 'Expiring < 1h',
            value: _fmtNum(sessions.expiringWithinHour),
            tip: 'A subset of Active. Without a created_at column this is the\nonly churn signal _jwt can offer.',
          ),
        ]),
        if (sessions.topUsers.isNotEmpty) ...[
          p(classes: 'dashboard-push-subtitle', [.text('Most sessions')]),
          div(classes: 'dashboard-session-users', [
            for (final user in sessions.topUsers)
              div(classes: 'dashboard-session-user', [
                span(classes: 'dashboard-cron-name', [.text(user.userId)]),
                span(classes: 'dashboard-session-user-count', [
                  .text(user.sessionCount == 1 ? '1 session' : '${_fmtNum(user.sessionCount)} sessions'),
                ]),
              ]),
          ]),
        ],
      ],
    ]);
  }
}

class _SessionFigure extends StatelessComponent {
  const _SessionFigure({required this.label, required this.value, required this.tip});

  final String label;
  final String value;
  final String tip;

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'dashboard-session-figure',
      events: appTooltipEvents(context, text: tip, placement: AppTooltipPlacement.belowLeft),
      [
        span(classes: 'dashboard-session-figure-value', [.text(value)]),
        span(classes: 'dashboard-stat-label', [.text(label)]),
      ],
    );
  }
}

class _StatCard extends StatelessComponent {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Component build(BuildContext context) {
    return div(classes: 'dashboard-stat-card', [
      span(classes: 'dashboard-stat-label', [.text(label)]),
      span(classes: 'dashboard-stat-value', [.text(value)]),
    ]);
  }
}

class _CronJobRow extends StatelessComponent {
  const _CronJobRow({required this.job, required this.isSubmitting, required this.showRun, required this.onRun});

  final CronJobSummary job;
  final bool isSubmitting;
  final bool showRun;
  final void Function() onRun;

  @override
  Component build(BuildContext context) {
    final isRunning = isSubmitting || job.inProgress;
    final status = isRunning
        ? 'running'
        : job.failed
        ? 'failed'
        : job.succeeded
        ? 'ok'
        : job.hasRun
        ? 'running'
        : 'pending';
    final statusLabel = switch (status) {
      'running' => 'Running',
      'failed' => 'Failed',
      'pending' => 'Never run',
      _ => 'Succeeded',
    };

    return div(
      classes: 'dashboard-cron-item dashboard-cron-item--$status',
      attributes: {'aria-label': '${job.name}, $statusLabel, ${_fmtCronMeta(job.lastStarted, job.duration)}'},
      [
        div(classes: 'dashboard-cron-main', [
          span(classes: 'dashboard-cron-name', [.text(job.name)]),
          span(classes: 'dashboard-cron-meta', [.text(_fmtCronMeta(job.lastStarted, job.duration))]),
        ]),
        if (showRun)
          ZonaiButton(
            variant: ZonaiButtonVariant.ghost,
            size: ZonaiButtonSize.sm,
            disabled: isRunning,
            onClick: onRun,
            child: .text(isRunning ? 'Running…' : 'Run'),
          ),
      ],
    );
  }
}

Component _dashboardRefreshIcon() {
  return svg(
    viewBox: '0 0 24 24',
    attributes: {
      'aria-hidden': 'true',
      'fill': 'none',
      'stroke': 'currentColor',
      'stroke-width': '2',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
    },
    classes: 'dashboard-refresh-icon',
    [
      path(d: 'M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8', []),
      path(d: 'M21 3v5h-5', []),
      path(d: 'M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16', []),
      path(d: 'M8 16H3v5', []),
    ],
  );
}

// ── Formatting ─────────────────────────────────────────────────────────────────

String _fmtNum(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _fmtPercent(double? p) {
  if (p == null) return '—';
  return '${p.toStringAsFixed(1)}%';
}

String _fmtMs(int? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(1)}s';
}

String _fmtHour(DateTime dt) {
  final h = dt.hour;
  if (h == 0) return '12am';
  if (h < 12) return '${h}am';
  if (h == 12) return '12pm';
  return '${h - 12}pm';
}

String _fmtDuration(Duration? d) {
  if (d == null) return '—';
  if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _fmtCronMeta(DateTime? lastStarted, Duration? duration) {
  if (lastStarted == null) return 'Never run';
  final ago = _timeAgo(lastStarted);
  final took = duration == null ? null : _fmtDuration(duration);
  if (took == null) return ago;
  return '$ago · $took';
}

/// The last drain, in one line.
///
/// Deliberately no count: nothing persists how many notifications a drain sent
/// (see [DashboardDrainRun]), so this says when it ran and whether it broke and
/// stops there rather than dressing a job count up as a delivery.
String _fmtDrain(DashboardDrainRun? run) {
  if (run == null) return 'Never';
  if (run.inProgress) return 'Running (started ${_timeAgo(run.startedAt)})';
  if (!run.succeeded) return 'Failed ${_timeAgo(run.failedAt ?? run.startedAt)}';
  return 'Succeeded ${_timeAgo(run.completedAt ?? run.startedAt)}';
}

String _fmtTableMeta(int? count) {
  if (count == null) return '—';
  if (count == 1) return '1 row';
  return '${_fmtNum(count)} rows';
}
