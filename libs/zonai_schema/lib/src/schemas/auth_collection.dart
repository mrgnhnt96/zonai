library auth_collection;

import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/column_types/email_column.dart';
import 'package:zonai_schema/src/column_types/password_column.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';

part 'auth/auth.dart';

abstract base class AuthCollection<T> extends Schema<T> implements Auth {
  AuthCollection(super.$);

  List<AuthType> get authTypes {
    if (this case final SupportedAuths auths) {
      return [if (auths.supportsPassword) .password];
    }

    throw UnimplementedError(
      '${runtimeType} is missing a `$SupportedAuths` mixin',
    );
  }
}

mixin AsAdmin on Auth {
  bool get canEdit => true;
}
