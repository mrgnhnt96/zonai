import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

typedef ForeignKeyPickerOnSelect = void Function(String? id, {String? displayLabel});

final class ForeignKeyPickerState {
  const ForeignKeyPickerState({
    required this.foreignKey,
    required this.selectedId,
    required this.onSelect,
  });

  final ForeignKeyShape foreignKey;
  final String? selectedId;
  final ForeignKeyPickerOnSelect onSelect;
}

final foreignKeyPickerProvider = NotifierProvider<ForeignKeyPickerNotifier, ForeignKeyPickerState?>(
  ForeignKeyPickerNotifier.new,
);

class ForeignKeyPickerNotifier extends Notifier<ForeignKeyPickerState?> {
  @override
  ForeignKeyPickerState? build() => null;

  void open({
    required ForeignKeyShape foreignKey,
    required String? selectedId,
    required ForeignKeyPickerOnSelect onSelect,
  }) {
    state = ForeignKeyPickerState(foreignKey: foreignKey, selectedId: selectedId, onSelect: onSelect);
  }

  void dismiss() => state = null;

  void confirmSelect(String? id, {String? displayLabel}) {
    final current = state;
    state = null;
    if (current != null) {
      current.onSelect(id, displayLabel: displayLabel);
    }
  }
}
