import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../theme/zonai_select.dart';

/// Select for bool, enum, and similar filter/edit values.
class TableEditSelect extends StatelessComponent {
  const TableEditSelect({
    super.key,
    required this.id,
    required this.shape,
    required this.value,
    required this.onChange,
    this.labelId,
    this.placeholder,
    this.boolAsYesNo = true,
    this.allowNullable = false,
    this.disabled = false,
  });

  final String id;
  final ColumnShape shape;
  final String value;
  final void Function(String value) onChange;
  final String? labelId;
  final String? placeholder;
  final bool boolAsYesNo;
  final bool allowNullable;
  final bool disabled;

  @override
  Component build(BuildContext context) {
    final options = _buildOptions();
    final effectivePlaceholder = allowNullable
        ? (placeholder ?? '—')
        : (placeholder ?? 'Choose value');
    return ZonaiSelect(
      id: id,
      value: value,
      options: options,
      placeholder: effectivePlaceholder,
      onChange: onChange,
      labelId: labelId,
      disabled: disabled,
    );
  }

  List<ZonaiSelectOption> _buildOptions() {
    if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
      if (boolAsYesNo) {
        return const [
          ZonaiSelectOption(value: 'true', label: 'Yes'),
          ZonaiSelectOption(value: 'false', label: 'No'),
        ];
      }
      return const [
        ZonaiSelectOption(value: 'true', label: 'true'),
        ZonaiSelectOption(value: 'false', label: 'false'),
      ];
    }

    if (shape.kind == ColumnShapeKind.enum_) {
      return [
        for (final v in shape.enumValues) ZonaiSelectOption(value: v, label: v),
      ];
    }

    return const [];
  }

  static String boolValueToSelectString(bool value) => value ? 'true' : 'false';

  static bool selectStringToBool(String value) => value == 'true';

  static bool? selectStringToNullableBool(String value) {
    if (value.isEmpty) return null;
    return selectStringToBool(value);
  }
}
