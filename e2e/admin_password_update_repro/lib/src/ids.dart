import 'package:zonai_schema/zonai_schema.dart' as z;

final class AdminsId implements z.Id {
  const AdminsId(this.value);

  static const _suffix = 'adm';

  factory AdminsId.generate() =>
      AdminsId('${DateTime.now().microsecondsSinceEpoch}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}

final class UsersId implements z.Id {
  const UsersId(this.value);

  static const _suffix = 'usr';

  factory UsersId.generate() =>
      UsersId('${DateTime.now().microsecondsSinceEpoch}_$_suffix');

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;
}
