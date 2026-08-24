import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class PasswordResetRequirementOperations
    extends
        TableOperations<
          PasswordResetRequirementTable,
          PasswordResetRequirement
        > {
  PasswordResetRequirementOperations() : super(passwordResetRequirements);
}

PasswordResetRequirementOperations main() =>
    PasswordResetRequirementOperations();
