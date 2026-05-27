import 'package:zonai/src/internal/tables/auth_challenge_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

AuthChallengeRowRules main() => AuthChallengeRowRules();

final class AuthChallengeRowRules
    extends InternalRowRules<AuthChallengeTable, AuthChallenge> {
  AuthChallengeRowRules() : super(authChallenges);

  @override
  Future<bool> canDelete(Jwt? jwt, AuthChallenge row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
