library auth_collection;

import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/column_types/email_column.dart';
import 'package:zonai_schema/src/column_types/is_verified_column.dart';
import 'package:zonai_schema/src/column_types/password_column.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';

part 'auth/auth.dart';

abstract base class AuthCollection<T> extends Schema<T> implements Auth {
  AuthCollection(super.$);

  List<AuthType> get authTypes {
    return [
      if (supportsPassword) .password,
      if (supportsOtp) .otp,
      if (supportsMagicLink) .magicLink,
    ];
  }

  bool get supportsPassword => false;
  bool get supportsOtp => false;
  bool get supportsMagicLink => false;
}

mixin AsAdmin on Auth {
  bool get canEdit => true;
}
