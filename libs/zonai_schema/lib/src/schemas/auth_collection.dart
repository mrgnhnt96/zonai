library auth;

import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/column_types/id_column.dart';
import 'package:zonai_schema/src/types/id.dart';

part 'password_auth.dart';

base class AuthCollection<T extends AuthCollection<T>> extends Schema<T>
    implements Auth {
  AuthCollection({
    required Id? id,
    required Id Function(String) fromString,
    required Id Function() generate,
    required SchemaBuilder<T> $,
  }) : id = $.id(
         'id',
         (s) => s.id,
         id,
         fromString: fromString,
         generate: generate,
       );

  final IdColumn<Id> id;

  AuthType get authType {
    if (this case final AuthType type) {
      return type;
    }

    throw UnimplementedError('${runtimeType} is missing an `$AuthType` mixin');
  }
}
