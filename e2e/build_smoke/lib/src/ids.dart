import 'package:zonai_schema/zonai_schema.dart' as z;

final class WidgetsId implements z.Id {
  const WidgetsId(this.value);

  static const _suffix = 'wgt';

  factory WidgetsId.generate() =>
      WidgetsId('${DateTime.now().microsecondsSinceEpoch}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
