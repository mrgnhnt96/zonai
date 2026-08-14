import 'package:zonai_schema/zonai_schema.dart' as z;

/// Ids are supplied by the driver rather than generated, so every assertion
/// can name the row it is about. [generate] exists because the id column
/// requires it, and is only reached if a create omits `id`.
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

final class GatesId implements z.Id {
  const GatesId(this.value);

  static const _suffix = 'gat';

  factory GatesId.generate() =>
      GatesId('${DateTime.now().microsecondsSinceEpoch}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
