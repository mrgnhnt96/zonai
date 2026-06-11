import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_routes.dart';
import '../constants/button_sizes.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/dashboard_provider.dart';
import '../providers/home_ui_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../utils/sqlite_table_utils.dart';
import 'home_settings_overlay.dart';
import 'home_sidebar.dart';
import 'theme/ui_styles.dart';
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
    final tableCounts = isClient ? context.watch(tableCountsProvider) : const AsyncValue<Map<String, int>>.loading();

    final statsData = metrics.value?.stats;
    final bucketsData = metrics.value?.buckets ?? [];
    final topErrorsData = topErrors.value ?? [];
    final cronJobsData = cronJobs.value ?? [];
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
              label(classes: 'dashboard-filter-label', [
                input<bool>(
                  type: InputType.checkbox,
                  classes: 'dashboard-filter-checkbox',
                  checked: excludeAdmin,
                  onChange: (_) => context.read(excludeAdminProvider.notifier).toggle(),
                ),
                .text('Exclude admin'),
              ]),
            ]),
            // Stat cards
            div(classes: 'dashboard-stats', [
              _StatCard(label: 'Requests (24h)', value: statsData != null ? _fmtNum(statsData.requestCount24h) : '—'),
              _StatCard(label: 'Error Rate', value: statsData != null ? _fmtPercent(statsData.errorRate) : '—'),
              _StatCard(label: 'p95 Response', value: statsData != null ? _fmtMs(statsData.p95ResponseMs) : '—'),
              _StatCard(label: 'Active Sessions', value: statsData != null ? _fmtNum(statsData.activeSessions) : '—'),
            ]),
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
                if (topErrors.isLoading)
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
            // Cron jobs
            div(classes: 'dashboard-panel', [
              p(classes: 'dashboard-panel-title', [.text('Cron Jobs')]),
              if (cronJobs.isLoading)
                div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [.text('Loading...')])
              else if (cronJobsData.isEmpty)
                div(classes: 'dashboard-panel-placeholder dashboard-panel-placeholder--sm', [
                  .text('No cron jobs found'),
                ])
              else
                div(classes: 'dashboard-cron-list', [
                  for (final job in cronJobsData)
                    div(classes: 'dashboard-cron-item', [
                      div(classes: 'dashboard-cron-left', [
                        span(classes: 'dashboard-cron-name', [.text(job.name)]),
                        span(classes: 'dashboard-cron-meta', [.text(_timeAgo(job.lastStarted))]),
                      ]),
                      div(classes: 'dashboard-cron-right', [
                        if (job.duration != null)
                          span(classes: 'dashboard-cron-duration', [.text(_fmtDuration(job.duration))]),
                        span(
                          classes:
                              'dashboard-cron-status dashboard-cron-status--${job.failed
                                  ? 'failed'
                                  : job.succeeded
                                  ? 'ok'
                                  : 'running'}',
                          [
                            .text(
                              job.failed
                                  ? 'Failed'
                                  : job.succeeded
                                  ? 'OK'
                                  : 'Running',
                            ),
                          ],
                        ),
                      ]),
                    ]),
                ]),
            ]),
            // Collections
            if (userTables.isNotEmpty)
              div(classes: 'dashboard-section', [
                div(classes: 'dashboard-section-header', [
                  p(classes: ZonaiClasses.sectionLabel, [.text('Tables')]),
                ]),
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
      css('.dashboard-panel--errors').styles(flex: Flex(grow: 0, shrink: 1), maxWidth: 400.px, minWidth: 240.px),
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
      css(
        '.dashboard-cron-list',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2)),
      css('.dashboard-cron-item').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        gap: Gap.all(ZonaiSpacing.s4),
        padding: .symmetric(vertical: ZonaiSpacing.s4, horizontal: ZonaiSpacing.s5),
        radius: .all(Radius.circular(8.px)),
        backgroundColor: bgColor,
        border: .all(color: borderColor, width: 1.px, style: .solid),
      ),
      css('.dashboard-cron-left').styles(
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
      css('.dashboard-cron-right').styles(
        display: .flex,
        flexDirection: FlexDirection.row,
        alignItems: .center,
        gap: Gap.all(ZonaiSpacing.s4),
        flex: Flex(grow: 0, shrink: 0),
      ),
      css('.dashboard-cron-duration').styles(fontSize: 0.6875.rem, color: mutedColor),
      css('.dashboard-cron-status').styles(
        fontSize: 0.6875.rem,
        fontWeight: .w600,
        padding: .symmetric(horizontal: ZonaiSpacing.s3, vertical: 3.px),
        radius: .all(Radius.circular(4.px)),
      ),
      css('.dashboard-cron-status--ok').styles(color: successColor, backgroundColor: successBgColor),
      css('.dashboard-cron-status--failed').styles(color: errorColor, backgroundColor: errorBgColor),
      css('.dashboard-cron-status--running').styles(color: mutedColor, backgroundColor: hoverColor),
      // Collections
      css(
        '.dashboard-section',
      ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s5)),
      css(
        '.dashboard-section-header',
      ).styles(display: .flex, flexDirection: FlexDirection.row, alignItems: .center, justifyContent: .spaceBetween),
      css(
        '.dashboard-section-link',
      ).styles(fontSize: 0.8125.rem, fontWeight: .w600, color: primaryColor, raw: const {'text-decoration': 'none'}),
      css('.dashboard-section-link:hover').styles(color: primaryHoverColor),
      css(
        '.dashboard-tables',
      ).styles(display: .flex, flexDirection: FlexDirection.row, flexWrap: .wrap, gap: Gap.all(ZonaiSpacing.s4)),
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
      css.media(MediaQuery.all(maxWidth: 1024.px), [css('.dashboard-tables').styles(justifyContent: .center)]),
      css.media(MediaQuery.all(maxWidth: 640.px), [css('.dashboard-header').styles(display: .none)]),
    ]),
  ];
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

String _fmtTableMeta(int? count) {
  if (count == null) return '—';
  if (count == 1) return '1 row';
  return '${_fmtNum(count)} rows';
}
