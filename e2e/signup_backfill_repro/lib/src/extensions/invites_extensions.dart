import 'package:zonai_signup_backfill_repro/src/schemas/invites.dart';
import 'package:zonai_schema/zonai_schema.dart';

InvitesExtensions main() => InvitesExtensions();

/// Queues a write from each `before*` hook, so a test can tell whether a
/// mutation queued ahead of the main write survives it.
///
/// The queued rows are marked by an `audit:` email prefix, and a hook ignores
/// any row that already carries it, so the audit rows' own hooks queue nothing.
final class InvitesExtensions extends Extension<Invite> {
  InvitesExtensions() : super(invites);

  static const auditPrefix = 'audit:';

  @override
  Future<void> beforeCreate(Invite object, Jwt? jwt) async {
    if (object.email.startsWith(auditPrefix)) return;

    mutate.create.one(
      tableName: 'invites',
      object: {'email': '${auditPrefix}before-create:${object.email}'},
    );
  }

  @override
  Future<void> beforeUpdate(Invite row, Jwt? jwt) async {
    if (row.email.startsWith(auditPrefix)) return;

    mutate.create.one(
      tableName: 'invites',
      object: {'email': '${auditPrefix}before-update:${row.email}'},
    );
  }

  @override
  Future<void> beforeDelete(Invite row, Jwt? jwt) async {
    if (row.email.startsWith(auditPrefix)) return;

    mutate.create.one(
      tableName: 'invites',
      object: {'email': '${auditPrefix}before-delete:${row.email}'},
    );
  }
}
