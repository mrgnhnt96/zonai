import 'package:zonai_schema/zonai_schema.dart' as z;

final class ItemsId implements z.Id {
  const ItemsId(this.value);

  static const _suffix = 'itm';

  factory ItemsId.generate() =>
      ItemsId('${DateTime.now().microsecondsSinceEpoch}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
