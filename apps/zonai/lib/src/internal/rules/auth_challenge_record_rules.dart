import 'package:zonai/src/internal/auth_challenge_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

AuthChallengeRecordRules main() => AuthChallengeRecordRules();

final class AuthChallengeRecordRules
    extends InternalRecordRules<AuthChallengeTable, AuthChallenge> {
  AuthChallengeRecordRules() : super(authChallenges);

  @override
  Future<bool> canDelete(Jwt? jwt, AuthChallenge record) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
