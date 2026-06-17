import 'dart:typed_data';

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/tables/photos_table.dart';

typedef TextColumn = ColumnType<String>;
typedef IntColumn = ColumnType<int>;
typedef BooleanColumn = ColumnType<bool>;
typedef RealColumn = ColumnType<double>;
typedef BigIntColumn = ColumnType<BigInt>;
typedef DateTimeColumn = ColumnType<DateTime>;
typedef BlobColumn = ColumnType<Uint8List>;

typedef EmailColumn = ColumnType<String>;
typedef PasswordColumn = ColumnType<String>;
typedef IsVerifiedColumn = ColumnType<bool>;
typedef EnumColumn<E extends Enum> = ColumnType<E>;
typedef EnumListColumn<E extends Enum> = ColumnType<List<E>>;
typedef PhotoColumn = ColumnType<PhotoId>;
typedef PhotosColumn = ColumnType<List<PhotoId>>;
typedef MapColumn = ColumnType<Map<String, dynamic>>;
typedef TypedMapColumn<T extends Object> = ColumnType<T>;
typedef ListColumn<T> = ColumnType<List<T>>;
