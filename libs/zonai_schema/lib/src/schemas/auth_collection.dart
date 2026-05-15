library auth_collection;

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/column_types/email_column.dart';
import 'package:zonai_schema/src/column_types/id_column.dart';
import 'package:zonai_schema/src/column_types/password_column.dart';
import 'package:zonai_schema/src/types/id.dart';

part 'auth/auth.dart';
part 'auth/auth_types.dart';

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
    if (this case _AuthType(:final authType)) {
      return authType;
    }

    throw UnimplementedError('${runtimeType} is missing an `$AuthType` mixin');
  }
}

mixin AsAdmin<T extends AuthCollection<T>> on Auth {
  bool get canEdit => true;
}
