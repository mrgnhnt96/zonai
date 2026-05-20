import 'package:zonai_schema/src/internal/auth_challenge_collection.dart';
import 'package:zonai_schema/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

AuthChallengeCollectionRules main() => AuthChallengeCollectionRules();

final class AuthChallengeCollectionRules
    extends InternalCollectionRules<AuthChallengeCollection, AuthChallenge> {
  AuthChallengeCollectionRules() : super(authChallenges);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
