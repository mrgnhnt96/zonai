library auth_collection;

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/column_types/email_column.dart';
import 'package:zonai_schema/src/column_types/password_column.dart';
import 'package:zonai_schema/src/types/id.dart';

part 'auth/auth.dart';
part 'auth/auth_types.dart';

abstract base class AuthCollection<T> extends Schema<T> implements Auth {
  AuthCollection(super.$);

  List<AuthType> get authTypes {
    if (this case SupportedAuths(:final authTypes)) {
      return authTypes;
    }

    throw UnimplementedError(
      '${runtimeType} is missing a `$SupportedAuths` mixin',
    );
  }
}

mixin AsAdmin on Auth {
  bool get canEdit => true;
}
