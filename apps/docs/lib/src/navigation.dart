/// The single source of truth for the docs site's information architecture.
///
/// Consumed by:
/// - `main.server.dart`, to render the sidebar, breadcrumbs and prev/next links.
/// - `tool/build_search_index.dart`, to label search results by section and to
///   assert that every page under `content/` is reachable from the sidebar.
///
/// Keep [navigation] ordered as a reading path: a developer who starts at the
/// top and works down should never hit a page that depends on one below it.
library;

/// A single page entry in the sidebar.
final class NavItem {
  const NavItem(this.title, this.href, {this.summary, this.badge});

  /// Link text, also used as the search result title.
  final String title;

  /// Root-absolute route, e.g. `/operations/streaming`.
  final String href;

  /// One-line description shown on section hub cards and in search results.
  ///
  /// Falls back to the page's own front matter `description` when null.
  final String? summary;

  /// Optional short label rendered next to the link, e.g. `new`.
  final String? badge;
}

/// A collapsible group of [NavItem]s in the sidebar.
final class NavGroup {
  const NavGroup(this.title, {required this.icon, required this.items, this.summary});

  /// The group heading, also used as the search result section label.
  final String title;

  /// Inline SVG markup rendered before [title]. See [NavIcons].
  final String icon;

  /// One-line description of what the group covers.
  final String? summary;

  final List<NavItem> items;
}

/// Pages that sit above the grouped navigation.
const List<NavItem> topLevelNavigation = [
  NavItem('Introduction', '/', summary: 'What Zonai is, what it gives you, and how a request flows through it.'),
];

/// The grouped sidebar navigation, in reading order.
const List<NavGroup> navigation = [
  NavGroup(
    'Start Here',
    icon: NavIcons.rocket,
    summary: 'Install the CLI and get a server answering requests.',
    items: [
      NavItem('Installation', '/getting-started/installation', summary: 'Prerequisites and installing the zonai CLI.'),
      NavItem('Quick Start', '/getting-started/quick-start', summary: 'Auth table, tasks table, migrate, serve — end to end.'),
      NavItem('Project Structure', '/getting-started/project-structure', summary: 'Directory layout, naming conventions, what to commit.'),
    ],
  ),
  NavGroup(
    'Core Concepts',
    icon: NavIcons.compass,
    summary: 'The model behind the framework — read this before going deep.',
    items: [
      NavItem('How a Request is Processed', '/core-concepts/request-pipeline', summary: 'The ordered pipeline, and what runs in-process vs. in a worker.'),
      NavItem('Workers', '/core-concepts/workers', summary: 'What workers are, when they run, and the pool/transport knobs.'),
      NavItem('Config Flavors', '/core-concepts/config-flavors', summary: 'Selecting dev, staging and prod configuration.'),
    ],
  ),
  NavGroup(
    'Configuration',
    icon: NavIcons.sliders,
    summary: 'Project settings, runtime config and secrets.',
    items: [
      NavItem('zonai.yaml Reference', '/configuration/zonai-yaml', summary: 'Every key in the project config file.'),
      NavItem('App Config', '/configuration/app-config', summary: 'AppConfig — base URL, JWT secret, SMTP, photos, workers.'),
      NavItem('Environment Variables', '/configuration/environment-variables', summary: 'Compile-time .env secrets and ZONAI_* runtime tuning.'),
    ],
  ),
  NavGroup(
    'Data Modeling',
    icon: NavIcons.table,
    summary: 'Define tables in Dart, then turn schema changes into SQL.',
    items: [
      NavItem('Defining Tables', '/schemas/defining-tables', summary: 'Table and entity classes, column helpers, typed IDs.'),
      NavItem('Auth Tables', '/schemas/auth-tables', summary: 'AuthTable plus the password, OTP and magic-link mixins.'),
      NavItem('Photo Tables', '/schemas/photo-tables', summary: 'The built-in _photos table and photo columns.'),
      NavItem('Migrations Overview', '/database/migrations-overview', summary: 'How a schema change becomes a migration.'),
      NavItem('Generating Migrations', '/database/generating-migrations', summary: 'zonai db migrate generate.'),
      NavItem('Applying Migrations', '/database/applying-migrations', summary: 'Applying migrations, and auto-migrate on serve.'),
    ],
  ),
  NavGroup(
    'Querying Data',
    icon: NavIcons.bolt,
    summary: 'The HTTP surface every table gets for free — including live streams.',
    items: [
      NavItem('Operations Overview', '/operations/overview', summary: 'Default vs. custom operations, and when to override the SQL.'),
      NavItem('Default Operations', '/operations/default-operations', summary: 'CRUD endpoints, request/response JSON, where and order_by shapes.'),
      NavItem('Live Queries', '/operations/streaming', badge: 'live', summary: 'db.listen and /db/stream* push updates — do not poll.'),
      NavItem('Auth Operations', '/operations/auth-operations', summary: 'Sign-up, sign-in, reset, OTP and magic-link routes.'),
      NavItem('OpenAPI Specification', '/api/openapi-spec', summary: 'Fetch the live OpenAPI JSON from a running server.'),
    ],
  ),
  NavGroup(
    'Rules & Authorization',
    icon: NavIcons.shield,
    summary: 'Deny-by-default checks that run before any SQL executes.',
    items: [
      NavItem('Rules Overview', '/rules/overview', summary: 'The two-layer table-then-row model, and default deny.'),
      NavItem('Table Rules', '/rules/table-rules', summary: 'Per-operation allow/deny decisions from the JWT.'),
      NavItem('Row Rules', '/rules/row-rules', summary: 'Per-row checks and requiresPerRowCheck.'),
      NavItem('Auth Rules', '/rules/auth-rules', summary: 'Gating sign-up, sign-in and password reset.'),
      NavItem('Photo Rules', '/rules/photo-rules', summary: 'Upload, view and delete access for photos.'),
      NavItem('JWT Claims', '/rules/jwt-claims', summary: 'Built-in claims and adding your own with addClaims.'),
    ],
  ),
  NavGroup(
    'Authentication',
    icon: NavIcons.key,
    summary: 'Password, OTP and magic-link sign-in, sessions and admins.',
    items: [
      NavItem('Overview', '/authentication/overview', summary: 'The JWT model, multi-table auth, and the response shape.'),
      NavItem('Password Auth', '/authentication/password-auth', summary: 'Email and password sign-in backed by Argon2id.'),
      NavItem('OTP Auth', '/authentication/otp-auth', summary: 'Emailed one-time passcodes.'),
      NavItem('Magic Link Auth', '/authentication/magic-link-auth', summary: 'Passwordless sign-in over emailed links.'),
      NavItem('Session Management', '/authentication/session-management', summary: 'Refresh, logout and JWT lifetime.'),
      NavItem('Admin Accounts', '/authentication/admin-accounts', summary: 'zonai db admin, the AsAdmin trait, elevated claims.'),
    ],
  ),
  NavGroup(
    'Extensions & Hooks',
    icon: NavIcons.plug,
    summary: 'Run your own Dart before and after each operation.',
    items: [
      NavItem('Overview', '/extensions/overview', summary: 'Where before/after hooks sit in the pipeline.'),
      NavItem('Create Hooks', '/extensions/create-hooks'),
      NavItem('Update Hooks', '/extensions/update-hooks'),
      NavItem('Delete Hooks', '/extensions/delete-hooks'),
      NavItem('Auth Hooks', '/extensions/auth-hooks'),
      NavItem('Side Effects: get', '/extensions/side-effects-get'),
      NavItem('Side Effects: mutate', '/extensions/side-effects-mutate'),
      NavItem('Side Effects: email', '/extensions/side-effects-email'),
    ],
  ),
  NavGroup(
    'Background Jobs',
    icon: NavIcons.clock,
    summary: 'Cron-scheduled work with full database access.',
    items: [
      NavItem('Overview', '/cron-jobs/overview', summary: 'How scheduled jobs are compiled and run.'),
      NavItem('Defining a Job', '/cron-jobs/defining-a-job'),
      NavItem('Catch-Up Logic', '/cron-jobs/catch-up-logic', summary: 'What happens to jobs missed while the server was down.'),
      NavItem('Side Effects', '/cron-jobs/side-effects'),
      NavItem('Running Manually', '/cron-jobs/running-manually'),
    ],
  ),
  NavGroup(
    'Email',
    icon: NavIcons.mail,
    summary: 'Transactional email over SMTP, with Mustache templates.',
    items: [
      NavItem('SMTP Setup', '/email/smtp-setup', summary: 'Point Zonai at an SMTP server.'),
      NavItem('Built-in Templates', '/email/built-in-templates', summary: 'The templates auth ships with.'),
      NavItem('Custom Templates', '/email/custom-templates'),
      NavItem('Testing Locally', '/email/testing-locally', summary: 'Catch outgoing mail during development.'),
    ],
  ),
  NavGroup(
    'Rate Limiting',
    icon: NavIcons.gauge,
    summary: 'Per-IP limits, applied before rules run.',
    items: [
      NavItem('Overview', '/rate-limiting/overview', summary: 'Where limits apply and what the defaults are.'),
      NavItem('Configuring Policies', '/rate-limiting/configuring-policies', summary: 'Per-table and per-operation policy classes.'),
      NavItem('Auth Rate Limits', '/rate-limiting/auth-rate-limits'),
      NavItem('Trusted Proxies', '/rate-limiting/trusted-proxies', summary: 'Getting the real client IP behind a proxy.'),
    ],
  ),
  NavGroup(
    'Dart Client',
    icon: NavIcons.dart,
    summary: 'zonai_client — a typed client so apps never hand-roll HTTP.',
    items: [
      NavItem('Overview', '/dart-client/overview', summary: 'Installing the generated client and setting baseUrl.'),
      NavItem('Authentication', '/dart-client/authentication', summary: 'Sign-in, token storage and refresh.'),
      NavItem('Database', '/dart-client/database', summary: 'CRUD plus db.listen live streams.'),
      NavItem('Photos', '/dart-client/photos'),
      NavItem('Email', '/dart-client/email'),
      NavItem('Storage', '/dart-client/storage', summary: 'Where the client persists tokens.'),
    ],
  ),
  NavGroup(
    'CLI Reference',
    icon: NavIcons.terminal,
    summary: 'Every zonai command and flag.',
    items: [
      NavItem('zonai dev', '/cli/dev', summary: 'Interactive TUI plus serve helpers.'),
      NavItem('zonai serve', '/cli/serve', summary: 'Run the development server.'),
      NavItem('zonai build', '/cli/build', summary: 'Produce the project-linked production binary.'),
      NavItem('zonai compile', '/cli/compile'),
      NavItem('zonai db', '/cli/db', summary: 'Migrations, admins, photos and logs.'),
      NavItem('zonai rules', '/cli/rules'),
      NavItem('zonai ai', '/cli/ai', summary: 'Install project-local assistant rules.'),
      NavItem('zonai version', '/cli/version'),
      NavItem('Upgrading Zonai', '/cli/upgrading', summary: 'Moving between releases, including breaking upgrades.'),
      NavItem('Global Flags', '/cli/global-flags'),
    ],
  ),
  NavGroup(
    'Deployment',
    icon: NavIcons.server,
    summary: 'Ship the binary and keep it running.',
    items: [
      NavItem('Building for Production', '/deployment/building-for-production', summary: 'zonai build and what it produces.'),
      NavItem('Running the Server', '/deployment/running-the-server'),
      NavItem('Server Binding', '/deployment/server-binding', summary: 'Host, port and listening on all interfaces.'),
      NavItem('Environment & Secrets', '/deployment/environment-and-secrets', summary: 'Getting secrets into a compiled binary.'),
      NavItem('Cross-Compilation', '/deployment/cross-compilation', summary: 'Building a Linux binary from macOS.'),
      NavItem('Deploying to Fly.io', '/deployment/fly-io', summary: 'A complete, worked deployment on Fly.io.'),
    ],
  ),
];

/// Pages that intentionally live outside the sidebar.
///
/// `tool/build_search_index.dart` checks every content page against
/// [navigation] and this set, so an unlisted new page fails the build rather
/// than quietly becoming unreachable.
const Set<String> unlistedRoutes = {'/about'};

/// Every navigable page, flattened into reading order.
List<NavItem> get flatNavigation => [
  ...topLevelNavigation,
  for (final group in navigation) ...group.items,
];

/// The group that owns [href], or null for a top-level or unlisted page.
NavGroup? groupFor(String href) {
  for (final group in navigation) {
    for (final item in group.items) {
      if (item.href == href) return group;
    }
  }
  return null;
}

/// The nav entry for [href], or null when the page is unlisted.
NavItem? itemFor(String href) {
  for (final item in flatNavigation) {
    if (item.href == href) return item;
  }
  return null;
}

/// The previous and next pages in reading order, for the page footer.
({NavItem? previous, NavItem? next}) neighborsOf(String href) {
  final flat = flatNavigation;
  final index = flat.indexWhere((item) => item.href == href);
  if (index < 0) return (previous: null, next: null);
  return (
    previous: index > 0 ? flat[index - 1] : null,
    next: index < flat.length - 1 ? flat[index + 1] : null,
  );
}

/// Inline SVG icons for [NavGroup]s.
///
/// Lucide-style 24x24 strokes so they inherit `currentColor` and line weight.
abstract final class NavIcons {
  static const String _open =
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';

  static const rocket =
      '$_open<path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/>'
      '<path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z"/>'
      '<path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0"/><path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5"/></svg>';

  static const compass =
      '$_open<circle cx="12" cy="12" r="10"/>'
      '<polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/></svg>';

  static const sliders =
      '$_open<line x1="4" x2="4" y1="21" y2="14"/><line x1="4" x2="4" y1="10" y2="3"/>'
      '<line x1="12" x2="12" y1="21" y2="12"/><line x1="12" x2="12" y1="8" y2="3"/>'
      '<line x1="20" x2="20" y1="21" y2="16"/><line x1="20" x2="20" y1="12" y2="3"/>'
      '<line x1="2" x2="6" y1="14" y2="14"/><line x1="10" x2="14" y1="8" y2="8"/>'
      '<line x1="18" x2="22" y1="16" y2="16"/></svg>';

  static const table =
      '$_open<path d="M12 3v18"/><rect width="18" height="18" x="3" y="3" rx="2"/>'
      '<path d="M3 9h18"/><path d="M3 15h18"/></svg>';

  static const bolt =
      '$_open<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>';

  static const shield =
      '$_open<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>'
      '<path d="m9 12 2 2 4-4"/></svg>';

  static const key =
      '$_open<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/>'
      '<path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/></svg>';

  static const plug =
      '$_open<path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/>'
      '<path d="M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/></svg>';

  static const clock =
      '$_open<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>';

  static const mail =
      '$_open<rect width="20" height="16" x="2" y="4" rx="2"/>'
      '<path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>';

  static const gauge =
      '$_open<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>';

  static const dart =
      '$_open<path d="M6 18 3.5 8.5 12 2l8.5 6.5L18 18Z"/><path d="M6 18h12"/>'
      '<path d="m12 2 6 16"/></svg>';

  static const terminal =
      '$_open<polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/></svg>';

  static const server =
      '$_open<rect width="20" height="8" x="2" y="2" rx="2"/><rect width="20" height="8" x="2" y="14" rx="2"/>'
      '<line x1="6" x2="6.01" y1="6" y2="6"/><line x1="6" x2="6.01" y1="18" y2="18"/></svg>';
}
