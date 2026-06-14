library auth_table;

import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart' hide Table;
import 'package:zonai_schema/src/column_types/column_type_aliases.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/supported_auths.dart';

part 'auth/auth.dart';

abstract base class AuthTable<T> extends Schema<T> implements Auth {
  AuthTable(super.$);

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
