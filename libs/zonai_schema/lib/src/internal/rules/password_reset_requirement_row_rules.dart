import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';

PasswordResetRequirementRowRules main() => PasswordResetRequirementRowRules();

/// Row half of [PasswordResetRequirementTableRules] — same admin-only
/// posture, inherited for the same reason.
final class PasswordResetRequirementRowRules
    extends
        InternalRowRules<
          PasswordResetRequirementTable,
          PasswordResetRequirement
        > {
  PasswordResetRequirementRowRules() : super(passwordResetRequirements);
}
