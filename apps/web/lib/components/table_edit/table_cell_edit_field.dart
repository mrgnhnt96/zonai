import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../../providers/foreign_key_picker_provider.dart';
import '../../providers/foreign_key_reference_validate_provider.dart';
import '../../providers/foreign_key_rows_provider.dart';
import '../../utils/table_cell_edit.dart';
import '../theme/ui_styles.dart';
import 'table_value_editor.dart';

const _validateDebounceDuration = Duration(milliseconds: 300);

/// Type-aware value editor for row detail edit mode.
class TableCellEditField extends StatefulComponent {
  const TableCellEditField({
    super.key,
    required this.id,
    required this.shape,
    required this.value,
    required this.textValue,
    required this.disabled,
    required this.onTextChanged,
    required this.onDraftChanged,
    this.labelId,
    this.onFkInvalidChanged,
    this.isPasswordReplaceMode,
    this.onEnablePasswordReplace,
  });

  final String id;
  final ColumnShape shape;
  final Object? value;
  final String textValue;
  final bool disabled;
  final void Function(String text) onTextChanged;
  final void Function(Object? value) onDraftChanged;
  final String? labelId;
  final void Function(bool invalid)? onFkInvalidChanged;
  final bool? isPasswordReplaceMode;
  final VoidCallback? onEnablePasswordReplace;

  @override
  State<TableCellEditField> createState() => _TableCellEditFieldState();
}

class _TableCellEditFieldState extends State<TableCellEditField> {
  String? _pickerDisplayLabel;
  var _fkSkipValidation = false;
  var _debouncedValidateText = '';
  var _lastReportedInvalid = false;
  Timer? _validateDebounce;

  @override
  void initState() {
    super.initState();
    if (isForeignKeyColumn(component.shape)) {
      _debouncedValidateText = component.textValue;
    }
  }

  @override
  void dispose() {
    _validateDebounce?.cancel();
    super.dispose();
  }

  void _openFkPicker() {
    if (component.disabled || component.shape.foreignKey == null) return;
    context
        .read(foreignKeyPickerProvider.notifier)
        .open(
          foreignKey: component.shape.foreignKey!,
          selectedId: component.textValue.isEmpty ? null : component.textValue,
          onSelect: (id, {displayLabel}) {
            _fkSkipValidation = true;
            _pickerDisplayLabel = displayLabel;
            _debouncedValidateText = id ?? '';
            _reportFkInvalid(false);
            component.onTextChanged(id ?? '');
            setState(() {});
          },
        );
  }

  void _onFkTextChanged(String text) {
    _fkSkipValidation = false;
    _pickerDisplayLabel = null;
    component.onTextChanged(text);
    _scheduleValidation(text);
    setState(() {});
  }

  void _scheduleValidation(String text) {
    _validateDebounce?.cancel();
    _validateDebounce = Timer(_validateDebounceDuration, () {
      if (!mounted) return;
      setState(() => _debouncedValidateText = text);
    });
  }

  void _reportFkInvalid(bool invalid) {
    if (_lastReportedInvalid == invalid) return;
    _lastReportedInvalid = invalid;
    final onFkInvalidChanged = component.onFkInvalidChanged;
    if (onFkInvalidChanged == null) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      onFkInvalidChanged(invalid);
    });
  }

  @override
  Component build(BuildContext context) {
    final shape = component.shape;
    final isFk = isForeignKeyColumn(shape) && shape.foreignKey != null;

    String? fkValidationError;
    var fkValidationLoading = false;
    String? validatedDisplayLabel;

    if (isFk && !_fkSkipValidation) {
      final trimmed = _debouncedValidateText.trim();
      if (trimmed.isEmpty) {
        _reportFkInvalid(false);
      } else {
        final query = ForeignKeyReferenceValidateQuery(
          foreignKey: shape.foreignKey!,
          columnShape: shape,
          valueText: _debouncedValidateText,
        );
        final asyncValidation = context.watch(foreignKeyReferenceValidateProvider(query));
        fkValidationLoading = asyncValidation.isLoading;
        switch (asyncValidation) {
          case AsyncData(:final value):
            validatedDisplayLabel = value.displayLabel;
            if (value.state == ForeignKeyReferenceValidation.invalid) {
              fkValidationError = foreignKeyReferenceInvalidMessage;
              _reportFkInvalid(true);
            } else {
              _reportFkInvalid(false);
            }
          case AsyncError():
            fkValidationError = foreignKeyReferenceInvalidMessage;
            _reportFkInvalid(true);
          case AsyncLoading():
            break;
        }
      }
    } else if (isFk) {
      _reportFkInvalid(false);
    }

    final fkDisplayLabel = _fkSkipValidation ? _pickerDisplayLabel : validatedDisplayLabel;

    final editor = TableValueEditor(
      id: component.id,
      shape: shape,
      value: component.value,
      textValue: component.textValue,
      disabled: component.disabled,
      labelId: component.labelId,
      onTextChanged: isFk ? _onFkTextChanged : component.onTextChanged,
      onDraftChanged: component.onDraftChanged,
      onBrowse: isFk ? _openFkPicker : null,
      inputClass: ZonaiClasses.input,
      allowNullableEnum: shape.isNullable,
      fkDisplayLabel: fkDisplayLabel,
      fkValidationError: fkValidationError,
      fkValidationLoading: fkValidationLoading,
      isPasswordReplaceMode: component.isPasswordReplaceMode,
      onEnablePasswordReplace: component.onEnablePasswordReplace,
    );

    return editor;
  }
}
