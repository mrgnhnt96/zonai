class DevMenuItem {
  const DevMenuItem(this.group, this.key, this.label, this.description);
  final String group;
  final String key;
  final String label;
  final String description;

  /// True when the action opens a form before running.
  bool get hasContent => switch (key) {
    'm' || 'n' || 'd' || 'a' || 'e' || 'v' || 't' || 'j' || 'f' || 'l' => true,
    _ => false,
  };
}

const devMenuItems = [
  DevMenuItem(
    'SERVER',
    's',
    'Start server',
    'Starts the local dev server so your app responds to requests.',
  ),
  DevMenuItem(
    'DATABASE',
    'u',
    'Apply migrations',
    'Runs any pending SQL migration files against your local database — keeps your schema in sync.',
  ),
  DevMenuItem(
    'DATABASE',
    'm',
    'Generate migration',
    'Detects schema changes since your last migration and generates the SQL to apply them. Name it after the change you made.',
  ),
  DevMenuItem(
    'DATABASE',
    'n',
    'Create schema',
    'Scaffolds a new schema file with an ID type and starter columns. Optionally generates and applies a migration right away.',
  ),
  DevMenuItem(
    'DATABASE',
    'd',
    'Clear database',
    'Deletes all rows from your local database for a clean slate. This cannot be undone.',
  ),
  DevMenuItem(
    'ADMIN',
    'a',
    'Create admin',
    'Seeds a new admin user into your local database so you can log in and test admin-only features.',
  ),
  DevMenuItem(
    'EMAIL',
    'e',
    'Send test email',
    'Delivers a rendered email template to a real inbox — use this to catch formatting or copy issues before shipping.',
  ),
  DevMenuItem(
    'EMAIL',
    'v',
    'Preview email',
    'Opens a rendered email template in your browser with your own variable values, no sending required.',
  ),
  DevMenuItem(
    'EMAIL',
    't',
    'Create email template',
    'Scaffolds a new HTML email template file in your project, ready to edit.',
  ),
  DevMenuItem(
    'WORKERS',
    'c',
    'Compile all',
    'Recompiles all worker executables from source. Run this after editing any worker code.',
  ),
  DevMenuItem(
    'WORKERS',
    'p',
    'Ping',
    'Checks that each compiled worker executable starts and responds — a quick sanity check after compiling.',
  ),
  DevMenuItem(
    'WORKERS',
    'j',
    'Run cron job',
    'Triggers a scheduled cron job immediately, outside its normal schedule. Useful for testing job logic on demand.',
  ),
  DevMenuItem(
    'WORKERS',
    'l',
    'Table rules',
    'Lists table-level permissions for every collection. Paste a JWT to see what that token can do on each table.',
  ),
  DevMenuItem(
    'WORKERS',
    'f',
    'Create part',
    'Generates a new worker source file (operation, rule, extension, or cron) from a template in the right location.',
  ),
];
