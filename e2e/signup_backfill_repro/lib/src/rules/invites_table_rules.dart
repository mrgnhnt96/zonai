import 'package:zonai_signup_backfill_repro/src/schemas/invites.dart';
import 'package:zonai_schema/zonai_schema.dart';

InviteTableRules main() => InviteTableRules();

final class InviteTableRules extends TableRules<InviteTable, Invite> {
  InviteTableRules() : super(invites);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
