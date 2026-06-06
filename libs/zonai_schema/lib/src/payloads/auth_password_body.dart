import 'dart:convert';

import 'package:meta/meta.dart';

sealed class AuthBody {
  const AuthBody({required this.table, required this.type});

  factory AuthBody.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      SignInAuthBody._type => SignInAuthBody.fromJson(json),
      SignUpAuthBody._type => SignUpAuthBody.fromJson(json),
      SendOtpAuthBody._type => SendOtpAuthBody.fromJson(json),
      SendMagicLinkAuthBody._type => SendMagicLinkAuthBody.fromJson(json),

      AdminSignInAuthBody._type => AdminSignInAuthBody.fromJson(json),
      AdminSendOtpAuthBody._type => AdminSendOtpAuthBody.fromJson(json),
      AdminSendMagicLinkAuthBody._type => AdminSendMagicLinkAuthBody.fromJson(
        json,
      ),

      _ => throw ArgumentError('Invalid auth body type: ${json['type']}'),
    };
  }

  factory AuthBody.signIn({
    required String table,
    required String email,
    required String password,
  }) = SignInAuthBody;

  factory AuthBody.signUp({
    required String table,
    required String email,
    required String password,
    required Map<String, dynamic> object,
  }) = SignUpAuthBody;

  factory AuthBody.sendOtp({
    required String table,
    required String email,
    Map<String, dynamic>? metadata,
  }) = SendOtpAuthBody;

  factory AuthBody.adminSendOtp({
    required String email,
    Map<String, dynamic>? metadata,
  }) = AdminSendOtpAuthBody;

  factory AuthBody.adminSignIn({
    required String email,
    required String password,
  }) = AdminSignInAuthBody;

  factory AuthBody.sendMagicLink({
    required String table,
    required String email,
    Map<String, dynamic>? metadata,
  }) = SendMagicLinkAuthBody;

  factory AuthBody.adminSendMagicLink({
    required String email,
    Map<String, dynamic>? metadata,
  }) = AdminSendMagicLinkAuthBody;

  final String table;
  final String type;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'table': table, 'type': type};
  }
}

abstract class AdminAuthBody {
  const AdminAuthBody({required this.type});

  factory AdminAuthBody.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      AdminSignInAuthBody._type => AdminSignInAuthBody.fromJson(json),
      AdminSendOtpAuthBody._type => AdminSendOtpAuthBody.fromJson(json),
      AdminVerifyOtpAuthBody._type => AdminVerifyOtpAuthBody.fromJson(json),
      AdminSendMagicLinkAuthBody._type => AdminSendMagicLinkAuthBody.fromJson(
        json,
      ),
      AdminVerifyMagicLinkAuthBody._type =>
        AdminVerifyMagicLinkAuthBody.fromJson(json),
      _ => throw ArgumentError('Invalid admin auth body type: ${json['type']}'),
    };
  }

  final String type;

  String get table =>
      throw UnimplementedError('$AdminAuthBody does not have a collection');

  @mustCallSuper
  Map<String, dynamic> toJson() => {'type': type};
}

class SendOtpAuthBody extends AuthBody {
  const SendOtpAuthBody({
    required this.email,
    required super.table,
    this.metadata,
  }) : super(type: _type);

  factory SendOtpAuthBody.fromJson(Map<String, dynamic> json) {
    return SendOtpAuthBody(
      email: json['email'] as String,
      table: json['table'] as String,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  static const _type = 'sendOtp';

  final String email;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'email': email,
    'metadata': metadata != null ? jsonDecode(jsonEncode(metadata)) : null,
  };
}

class AdminSendOtpAuthBody extends AdminAuthBody implements SendOtpAuthBody {
  const AdminSendOtpAuthBody({required this.email, this.metadata})
    : super(type: _type);

  factory AdminSendOtpAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminSendOtpAuthBody(
      email: json['email'] as String,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  static const _type = 'adminSendOtp';

  final String email;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'email': email,
    'metadata': metadata != null ? jsonDecode(jsonEncode(metadata)) : null,
  };
}

class VerifyOtpAuthBody extends VerifyAuthBody {
  const VerifyOtpAuthBody({required this.email, required this.code})
    : super(type: _type);

  factory VerifyOtpAuthBody.fromJson(Map<String, dynamic> json) {
    return VerifyOtpAuthBody(
      email: json['email'] as String,
      code: json['code'] as String,
    );
  }

  static const _type = 'verifyOtp';

  final String email;
  final String code;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'email': email,
    'code': code,
  };
}

class AdminVerifyOtpAuthBody extends AdminAuthBody
    implements VerifyOtpAuthBody {
  const AdminVerifyOtpAuthBody({required this.email, required this.code})
    : super(type: _type);

  factory AdminVerifyOtpAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminVerifyOtpAuthBody(
      email: json['email'] as String,
      code: json['code'] as String,
    );
  }

  static const _type = 'adminVerifyOtp';

  final String email;
  final String code;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'email': email,
    'code': code,
  };
}

class SendMagicLinkAuthBody extends AuthBody {
  const SendMagicLinkAuthBody({
    required this.email,
    required super.table,
    this.metadata,
  }) : super(type: _type);

  factory SendMagicLinkAuthBody.fromJson(Map<String, dynamic> json) {
    return SendMagicLinkAuthBody(
      email: json['email'] as String,
      table: json['table'] as String,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  static const _type = 'sendMagicLink';

  final String email;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'email': email,
    'metadata': metadata != null ? jsonDecode(jsonEncode(metadata)) : null,
  };
}

class AdminSendMagicLinkAuthBody extends AdminAuthBody
    implements SendMagicLinkAuthBody {
  const AdminSendMagicLinkAuthBody({required this.email, this.metadata})
    : super(type: _type);

  factory AdminSendMagicLinkAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminSendMagicLinkAuthBody(
      email: json['email'] as String,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  static const _type = 'adminSendMagicLink';

  final String email;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'email': email,
    'metadata': metadata != null ? jsonDecode(jsonEncode(metadata)) : null,
  };
}

sealed class VerifyAuthBody {
  const VerifyAuthBody({required this.type});

  factory VerifyAuthBody.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      VerifyOtpAuthBody._type => VerifyOtpAuthBody.fromJson(json),
      VerifyMagicLinkAuthBody._type => VerifyMagicLinkAuthBody.fromJson(json),

      AdminVerifyOtpAuthBody._type => AdminVerifyOtpAuthBody.fromJson(json),
      AdminVerifyMagicLinkAuthBody._type =>
        AdminVerifyMagicLinkAuthBody.fromJson(json),

      ConfirmResetPasswordAuthBody._type =>
        ConfirmResetPasswordAuthBody.fromJson(json),

      ConfirmVerifyEmailAuthBody._type => ConfirmVerifyEmailAuthBody.fromJson(
        json,
      ),

      _ => throw ArgumentError(
        'Invalid verify auth body type: ${json['type']}',
      ),
    };
  }

  factory VerifyAuthBody.verifyOtp({
    required String email,
    required String code,
  }) = VerifyOtpAuthBody;

  factory VerifyAuthBody.adminVerifyOtp({
    required String email,
    required String code,
  }) = AdminVerifyOtpAuthBody;

  factory VerifyAuthBody.verifyMagicLink({required String secret}) =
      VerifyMagicLinkAuthBody;

  factory VerifyAuthBody.adminVerifyMagicLink({required String secret}) =
      AdminVerifyMagicLinkAuthBody;

  factory VerifyAuthBody.confirmResetPassword({
    required String token,
    required String newPassword,
  }) = ConfirmResetPasswordAuthBody;

  factory VerifyAuthBody.confirmVerifyEmail({required String token}) =
      ConfirmVerifyEmailAuthBody;

  final String type;

  @mustCallSuper
  Map<String, dynamic> toJson() => {'type': type};
}

class VerifyMagicLinkAuthBody extends VerifyAuthBody {
  const VerifyMagicLinkAuthBody({required this.secret}) : super(type: _type);

  factory VerifyMagicLinkAuthBody.fromJson(Map<String, dynamic> json) {
    return VerifyMagicLinkAuthBody(secret: json['secret'] as String);
  }

  static const _type = 'verifyMagicLink';

  final String secret;

  Map<String, dynamic> toJson() => {...super.toJson(), 'secret': secret};
}

class AdminVerifyMagicLinkAuthBody extends AdminAuthBody
    implements VerifyMagicLinkAuthBody {
  const AdminVerifyMagicLinkAuthBody({required this.secret})
    : super(type: _type);

  factory AdminVerifyMagicLinkAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminVerifyMagicLinkAuthBody(secret: json['secret'] as String);
  }

  static const _type = 'adminVerifyMagicLink';

  final String secret;

  Map<String, dynamic> toJson() => {...super.toJson(), 'secret': secret};
}

sealed class ResetPasswordAuthBody {
  const ResetPasswordAuthBody({required this.type, required this.email});

  factory ResetPasswordAuthBody.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      SendResetPasswordAuthBody._type => SendResetPasswordAuthBody.fromJson(
        json,
      ),
      AdminSendResetPasswordAuthBody._type =>
        AdminSendResetPasswordAuthBody.fromJson(json),
      _ => throw ArgumentError(
        'Invalid reset password auth body type: ${json['type']}',
      ),
    };
  }

  final String type;
  final String email;

  @mustCallSuper
  Map<String, dynamic> toJson() => {'type': type, 'email': email};
}

class SendResetPasswordAuthBody extends ResetPasswordAuthBody {
  const SendResetPasswordAuthBody({required super.email, required this.table})
    : super(type: _type);

  factory SendResetPasswordAuthBody.fromJson(Map<String, dynamic> json) {
    return SendResetPasswordAuthBody(
      email: json['email'] as String,
      table: json['table'] as String,
    );
  }

  static const _type = 'sendResetPassword';

  final String table;

  Map<String, dynamic> toJson() => {...super.toJson(), 'table': table};
}

class AdminSendResetPasswordAuthBody extends ResetPasswordAuthBody {
  const AdminSendResetPasswordAuthBody({required super.email})
    : super(type: _type);

  factory AdminSendResetPasswordAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminSendResetPasswordAuthBody(email: json['email'] as String);
  }

  static const _type = 'adminSendResetPassword';

  Map<String, dynamic> toJson() => {...super.toJson()};
}

class ConfirmResetPasswordAuthBody extends VerifyAuthBody {
  const ConfirmResetPasswordAuthBody({
    required this.token,
    required this.newPassword,
  }) : super(type: _type);

  factory ConfirmResetPasswordAuthBody.fromJson(Map<String, dynamic> json) {
    return ConfirmResetPasswordAuthBody(
      token: json['token'] as String,
      newPassword: json['newPassword'] as String,
    );
  }

  static const _type = 'confirmResetPassword';

  final String token;
  final String newPassword;

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'token': token,
    'newPassword': newPassword,
  };
}

class VerifyEmailAuthBody {
  const VerifyEmailAuthBody({required this.email, required this.table});

  factory VerifyEmailAuthBody.fromJson(Map<String, dynamic> json) {
    return VerifyEmailAuthBody(
      email: json['email'] as String,
      table: json['table'] as String,
    );
  }

  final String email;
  final String table;

  @mustCallSuper
  Map<String, dynamic> toJson() => {'email': email, 'table': table};
}

class ConfirmVerifyEmailAuthBody extends VerifyAuthBody {
  const ConfirmVerifyEmailAuthBody({required this.token}) : super(type: _type);

  factory ConfirmVerifyEmailAuthBody.fromJson(Map<String, dynamic> json) {
    return ConfirmVerifyEmailAuthBody(token: json['token'] as String);
  }

  static const _type = 'confirmVerifyEmail';

  final String token;

  Map<String, dynamic> toJson() => {...super.toJson(), 'token': token};
}

class AdminSignInAuthBody extends AdminAuthBody implements SignInAuthBody {
  const AdminSignInAuthBody({required this.email, required this.password})
    : super(type: _type);

  static const _type = 'adminSignIn';

  final String email;
  final String password;

  factory AdminSignInAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminSignInAuthBody(
      email: json['email'] as String,
      password: json['password'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'email': email, 'password': password};
  }
}

class SignInAuthBody extends AuthBody {
  const SignInAuthBody({
    required super.table,
    required this.email,
    required this.password,
  }) : super(type: _type);

  static const _type = 'signIn';

  final String email;
  final String password;

  factory SignInAuthBody.fromJson(Map<String, dynamic> json) {
    return SignInAuthBody(
      table: json['table'] as String,
      email: json['email'] as String,
      password: json['password'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'email': email, 'password': password};
  }
}

class SignUpAuthBody extends AuthBody {
  const SignUpAuthBody({
    required super.table,
    required this.email,
    required this.password,
    this.object,
  }) : super(type: _type);

  static const _type = 'signUp';

  final String email;
  final String password;
  final Map<String, dynamic>? object;

  factory SignUpAuthBody.fromJson(Map<String, dynamic> json) {
    return SignUpAuthBody(
      table: json['table'] as String,
      email: json['email'] as String,
      password: json['password'] as String,
      object: json['object'] != null
          ? Map<String, dynamic>.from(json['object'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'email': email,
      'password': password,
      'object': ?object,
    };
  }
}
