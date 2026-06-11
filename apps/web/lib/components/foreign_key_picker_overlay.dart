import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../providers/foreign_key_picker_provider.dart';
import 'table_edit/foreign_key_picker_dialog.dart';

/// FK browse dialog rendered at the app shell so it is not clipped by side panels.
class ForeignKeyPickerOverlay extends StatelessComponent {
  const ForeignKeyPickerOverlay({super.key});

  @override
  Component build(BuildContext context) {
    final picker = context.watch(foreignKeyPickerProvider);
    if (picker == null) {
      return Component.empty();
    }

    final notifier = context.read(foreignKeyPickerProvider.notifier);
    return ForeignKeyPickerDialog(
      foreignKey: picker.foreignKey,
      selectedId: picker.selectedId,
      onSelect: picker.onSelect,
      onClose: notifier.dismiss,
    );
  }

  @css
  static List<StyleRule> get styles => foreignKeyPickerDialogStyles;
}
