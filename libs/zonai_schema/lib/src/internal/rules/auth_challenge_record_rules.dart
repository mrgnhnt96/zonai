import 'package:zonai_schema/src/internal/auth_challenge_collection.dart';
import 'package:zonai_schema/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

AuthChallengeRecordRules main() => AuthChallengeRecordRules();

final class AuthChallengeRecordRules
    extends InternalRecordRules<AuthChallengeCollection, AuthChallenge> {
  AuthChallengeRecordRules() : super(authChallenges);

  @override
  Future<bool> canDelete(Jwt? jwt, AuthChallenge record) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
