import 'package:zonai/src/internal/tables/auth_challenge_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class AuthChallengeOperations
    extends TableOperations<AuthChallengeTable, AuthChallenge> {
  AuthChallengeOperations() : super(authChallenges);
}

AuthChallengeOperations main() => AuthChallengeOperations();
