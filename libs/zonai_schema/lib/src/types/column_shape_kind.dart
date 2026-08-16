/// Semantic column type for admin UI and API consumers.
enum ColumnShapeKind {
  text,
  integer,
  real,
  boolean,
  blob,
  bigInt,
  dateTime,
  email,
  password,
  id,
  photo,
  photos,
  deviceToken,
  isVerified,
  enum_,
  enumList,
  map,
  list,
  createdAt,
  updatedAt;

  String toJson() => switch (this) {
    ColumnShapeKind.enum_ => 'enum',
    _ => name,
  };

  static ColumnShapeKind fromJson(String value) => switch (value) {
    'enum' => ColumnShapeKind.enum_,
    _ => ColumnShapeKind.values.byName(value),
  };
}
