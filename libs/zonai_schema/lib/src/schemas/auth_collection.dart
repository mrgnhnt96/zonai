library auth_collection;

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/column_types/email_column.dart';
import 'package:zonai_schema/src/column_types/password_column.dart';
import 'package:zonai_schema/src/types/id.dart';

part 'auth/auth.dart';
part 'auth/auth_types.dart';

abstract base class AuthCollection<T> extends Schema<T> implements Auth {
  AuthCollection(super.$);

  AuthType get authType {
    if (this case _AuthType(:final authType)) {
      return authType;
    }

    throw UnimplementedError('${runtimeType} is missing an `$AuthType` mixin');
  }
}

mixin AsAdmin on Auth {
  bool get canEdit => true;
}
