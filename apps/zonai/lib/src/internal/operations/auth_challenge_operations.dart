import 'package:zonai/src/internal/auth_challenge_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

final class AuthChallengeOperations
    extends CollectionOperations<AuthChallengeCollection, AuthChallenge> {
  AuthChallengeOperations() : super(authChallenges);
}

AuthChallengeOperations main() => AuthChallengeOperations();
