import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: $json');
    }

    return switch (parts[1]) {
      AuthorsId._suffix => AuthorsId(json),
      CompaniesId._suffix => CompaniesId(json),
      ItemsId._suffix => ItemsId(json),
      PostsId._suffix => PostsId(json),
      UsersId._suffix => UsersId(json),
      CellEditFixturesId._suffix => CellEditFixturesId(json),
      _ => throw ArgumentError('Invalid ID format: $json'),
    };
  }

  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is z.Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class AuthorsId extends Id {
  const AuthorsId(super.value);

  factory AuthorsId.generate() => AuthorsId(z.Id.generate(_suffix));

  static const _suffix = 'au';
}

class CompaniesId extends Id {
  const CompaniesId(super.value);

  factory CompaniesId.generate() => CompaniesId(z.Id.generate(_suffix));

  static const _suffix = 'co';
}

class ItemsId extends Id {
  const ItemsId(super.value);

  factory ItemsId.generate() => ItemsId(z.Id.generate(_suffix));

  static const _suffix = 'it';
}

class PostsId extends Id {
  const PostsId(super.value);

  factory PostsId.generate() => PostsId(z.Id.generate(_suffix));

  static const _suffix = 'po';
}

class UsersId extends Id {
  const UsersId(super.value);

  factory UsersId.generate() => UsersId(z.Id.generate(_suffix));

  static const _suffix = 'us';
}

class CellEditFixturesId extends Id {
  const CellEditFixturesId(super.value);

  factory CellEditFixturesId.generate() =>
      CellEditFixturesId(z.Id.generate(_suffix));

  static const _suffix = 'cf';
}
