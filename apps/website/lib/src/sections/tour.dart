/// A short tour of the four files you actually touch.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../interactive/code_tabs.dart';
import '../theme.dart';
import '../ui.dart';

const _rules = r'''
TaskTableRules main() => TaskTableRules();

final class TaskTableRules extends TableRules<TaskTable, Task> {
  TaskTableRules() : super(tasks);

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
}

// Anything you do not override defaults to false. Deny by default.
''';

const _auth = r'''
final class UserTable extends AuthTable<User> with PasswordAuth {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: UsersId.new, generate: UsersId.generate),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final CreatedAtColumn createdAt;
  final UpdatedAtColumn updatedAt;
}

final users = authTable('users', UserTable.new);

// One mixin, and sign-up, sign-in, refresh and logout exist.
// Swap in OtpAuth or MagicLinkAuth for the other flows.
''';

const _cron = r'''
final class DailyReportJob extends CronJob {
  DailyReportJob()
    : super(
        name: 'daily-report',
        schedule: Schedule.parse('0 8 * * *'), // 8:00 AM daily
      );

  @override
  Future<void> run() async {
    // Full database API available in here.
  }
}

DailyReportJob main() => DailyReportJob();
''';

const _cli = r'''
$ ./zonai dev                       # watch + recompile workers, TUI dashboard
$ ./zonai db migrate generate -n add-status
$ ./zonai db migrate apply          # apply pending migrations
$ ./zonai rules list                # what does each table allow?
$ ./zonai rules table tasks update  # check one op, optionally --jwt <token>
$ ./zonai build                     # link the project into build/zonai
$ ./zonai ai claude                 # write assistant rules into the repo
''';

class Tour extends StatelessComponent {
  const Tour({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      eyebrow: 'The tour',
      title: .fragment([.text('Four files and a '), accent('CLI'), .text('.')]),
      lede:
          'A Zonai project is mostly schemas and rules. Everything else — routing, serialization, session handling, '
          'migrations — is the framework’s problem.',
      children: [
        const CodeTabs(
          labels: ['Rules', 'Auth', 'Cron', 'CLI'],
          filenames: [
            'lib/src/rules/tasks_table_rules.dart',
            'lib/src/schemas/users.dart',
            'lib/src/crons/daily_report.dart',
            'terminal',
          ],
          sources: [_rules, _auth, _cron, _cli],
          langs: ['dart', 'dart', 'dart', 'shell'],
          captions: [
            'Rules are evaluated before any SQL runs. Every method you do not override denies by default, so a '
                'forgotten rule fails closed rather than leaking a table.',
            'Mixing PasswordAuth into an auth table is what creates the sign-up, sign-in, refresh and logout routes. '
                'OtpAuth and MagicLinkAuth are the other two.',
            'Cron jobs compile into their own worker. strict controls whether runs missed during downtime are caught '
                'up or skipped.',
            './zonai dev watches worker sources and recompiles them as you edit. Restart serve after changing ops or '
                'rules, since those are linked into the binary.',
          ],
        ),

        div(classes: 'tour-foot', [
          docsLink('Read the quick start', Links.quickStart),
          docsLink('Browse the CLI reference', Links.docs),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.tour-foot').styles(
      display: .flex,
      margin: .only(top: 28.px),
      flexWrap: .wrap,
      gap: .all(26.px),
    ),
  ];
}
