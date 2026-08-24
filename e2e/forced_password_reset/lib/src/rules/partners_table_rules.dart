import 'package:zonai_forced_password_reset/src/schemas/partners.dart';
import 'package:zonai_schema/zonai_schema.dart';

PartnerTableRules main() => PartnerTableRules();

final class PartnerTableRules extends AuthTableRules<PartnerTable, Partner> {
  PartnerTableRules() : super(partners);

  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
