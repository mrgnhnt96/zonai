import 'package:zonai_forced_password_reset/src/schemas/partners.dart';
import 'package:zonai_schema/zonai_schema.dart';

PartnerRowRules main() => PartnerRowRules();

final class PartnerRowRules extends AuthRowRules<PartnerTable, Partner> {
  PartnerRowRules() : super(partners);

  @override
  Future<bool> canView(Jwt? jwt, Partner row) async => true;
}
