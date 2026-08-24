import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';

PasswordResetRequirementTableRules main() =>
    PasswordResetRequirementTableRules();

/// Admin-only, by inheritance. [BaseTableRules] already answers `canCreate`,
/// `canUpdate` and `canDelete` with `jwt.admin.canEdit` and `canView` with
/// `jwt.admin.isAdmin`, which is exactly the posture this table wants — a
/// requirement must not be readable or clearable by the account it
/// constrains (`docs/force-password-reset-design.md` §1).
///
/// Nothing is overridden on purpose: restating the defaults here would be a
/// second copy of the same policy that could drift from the first.
final class PasswordResetRequirementTableRules
    extends
        InternalTableRules<
          PasswordResetRequirementTable,
          PasswordResetRequirement
        > {
  PasswordResetRequirementTableRules() : super(passwordResetRequirements);
}
