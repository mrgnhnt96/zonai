import 'package:nocterm/nocterm.dart';
import 'package:zonai_schema/payloads.dart';

import '../dev_form_options.dart';
import '../actions/part_scaffold.dart';
import '../actions/schema_scaffold.dart';
import '../../../utils/schema_tables.dart';
import 'dev_admin_form.dart';
import 'dev_confirm_form.dart';
import 'dev_cron_form.dart';
import 'dev_email_preview_form.dart';
import 'dev_email_test_form.dart';
import 'dev_input_mode.dart';
import 'dev_migrate_form.dart';
import 'dev_part_form.dart';
import 'dev_rules_form.dart';
import 'dev_schema_form.dart';
import 'dev_text_form.dart';

class DevInputPanel extends StatelessComponent {
  const DevInputPanel({
    required this.inputMode,
    required this.adminExtraFields,
    required this.formOptions,
    this.adminShapeError,
    required this.onMigrateCancel,
    required this.onMigrateGenerateSubmit,
    required this.onAdminCancel,
    required this.onAdminSubmit,
    required this.onEmailTestCancel,
    required this.onEmailTestSubmit,
    required this.onEmailPreviewCancel,
    required this.onEmailPreviewSubmit,
    required this.onEmailTemplateCancel,
    required this.onEmailTemplateSubmit,
    required this.onCronCancel,
    required this.onCronSubmit,
    required this.onClearCancel,
    required this.onClearConfirm,
    required this.onCreatePartCancel,
    required this.onCreatePartSubmit,
    required this.onCreateSchemaCancel,
    required this.onCreateSchemaSubmit,
    required this.onRulesCancel,
    required this.onRulesSubmit,
    super.key,
  });

  final DevInputMode inputMode;
  final List<ColumnShape> adminExtraFields;
  final DevFormOptions formOptions;
  final String? adminShapeError;
  final VoidCallback onMigrateCancel;
  final void Function(String name) onMigrateGenerateSubmit;
  final VoidCallback onAdminCancel;
  final void Function(
    String email,
    String password,
    Map<String, String> extraFields,
  )
  onAdminSubmit;
  final VoidCallback onEmailTestCancel;
  final void Function(String to, String template) onEmailTestSubmit;
  final VoidCallback onEmailPreviewCancel;
  final void Function(String template, Map<String, String> variables)
  onEmailPreviewSubmit;
  final VoidCallback onEmailTemplateCancel;
  final void Function(String name) onEmailTemplateSubmit;
  final VoidCallback onCronCancel;
  final void Function(String name) onCronSubmit;
  final VoidCallback onClearCancel;
  final VoidCallback onClearConfirm;
  final VoidCallback onCreatePartCancel;
  final bool Function(
    WorkerPartType partType,
    String className,
    SchemaTableInfo? table,
  )
  onCreatePartSubmit;
  final VoidCallback onCreateSchemaCancel;
  final bool Function(
    String entityName,
    SchemaTableKind tableKind,
    SchemaAuthConfig authConfig,
    bool runMigration,
  )
  onCreateSchemaSubmit;
  final VoidCallback onRulesCancel;
  final void Function(String? jwt) onRulesSubmit;

  @override
  Component build(BuildContext context) {
    return switch (inputMode) {
      DevInputMode.migrateGenerate => DevMigrateForm(
        onCancel: onMigrateCancel,
        onSubmit: onMigrateGenerateSubmit,
      ),
      DevInputMode.adminEmail || DevInputMode.adminPassword => DevAdminForm(
        extraFields: adminExtraFields,
        loadError: adminShapeError,
        onCancel: onAdminCancel,
        onSubmit: onAdminSubmit,
      ),
      DevInputMode.emailTest => DevEmailTestForm(
        emailTemplates: formOptions.emailTemplates,
        onCancel: onEmailTestCancel,
        onSubmit: onEmailTestSubmit,
      ),
      DevInputMode.emailPreview => DevEmailPreviewForm(
        emailTemplates: formOptions.emailTemplates,
        onCancel: onEmailPreviewCancel,
        onPreview: onEmailPreviewSubmit,
      ),
      DevInputMode.emailTemplate => DevTextForm(
        title: 'Create Email Template',
        label: 'Template name:',
        placeholder: 'welcome_email',
        onCancel: onEmailTemplateCancel,
        onSubmit: onEmailTemplateSubmit,
      ),
      DevInputMode.cronRun => DevCronForm(
        cronJobNames: formOptions.cronJobNames,
        onCancel: onCronCancel,
        onSubmit: onCronSubmit,
      ),
      DevInputMode.clearDatabase => DevConfirmForm(
        title: 'Clear Database',
        message: 'Delete the local SQLite database file and WAL sidecars?',
        onCancel: onClearCancel,
        onConfirm: onClearConfirm,
      ),
      DevInputMode.createPart => DevPartForm(
        schemaTables: formOptions.schemaTables,
        onCancel: onCreatePartCancel,
        onSubmit: onCreatePartSubmit,
      ),
      DevInputMode.createSchema => DevSchemaForm(
        onCancel: onCreateSchemaCancel,
        onSubmit: onCreateSchemaSubmit,
      ),
      DevInputMode.rulesJwt => DevRulesForm(
        onCancel: onRulesCancel,
        onSubmit: onRulesSubmit,
      ),
      DevInputMode.none || DevInputMode.migrateApply => Container(),
    };
  }
}
