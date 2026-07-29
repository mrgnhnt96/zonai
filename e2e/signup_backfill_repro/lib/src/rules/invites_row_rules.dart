import 'package:zonai_signup_backfill_repro/src/schemas/invites.dart';
import 'package:zonai_schema/zonai_schema.dart';

InviteRowRules main() => InviteRowRules();

class InviteRowRules extends RowRules<InviteTable, Invite> {
  InviteRowRules() : super(invites);

  @override
  Future<bool> canView(Jwt? jwt, Invite row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Invite row) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Invite row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Invite row) async => true;
}
