import 'dart:convert';

import 'package:meta/meta.dart';

sealed class AuthBody {
  const AuthBody({required this.collection, required this.type});

  factory AuthBody.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      SignInAuthBody._type => SignInAuthBody.fromJson(json),
      SignUpAuthBody._type => SignUpAuthBody.fromJson(json),
      SendOtpAuthBody._type => SendOtpAuthBody.fromJson(json),
      VerifyOtpAuthBody._type => VerifyOtpAuthBody.fromJson(json),

      AdminSignInAuthBody._type => AdminSignInAuthBody.fromJson(json),
      AdminSendOtpAuthBody._type => AdminSendOtpAuthBody.fromJson(json),
      AdminVerifyOtpAuthBody._type => AdminVerifyOtpAuthBody.fromJson(json),

      _ => throw ArgumentError('Invalid auth body type: ${json['type']}'),
    };
  }

  factory AuthBody.signIn({
    required String collection,
    required String email,
    required String password,
  }) = SignInAuthBody;

  factory AuthBody.signUp({
    required String collection,
    required String email,
    required String password,
    required Map<String, dynamic> object,
  }) = SignUpAuthBody;

  factory AuthBody.sendOtp({
    required String collection,
    required String email,
    Map<String, dynamic>? metadata,
  }) = SendOtpAuthBody;

  factory AuthBody.verifyOtp({
    required String collection,
    required String email,
    required String code,
  }) = VerifyOtpAuthBody;

  factory AuthBody.adminSendOtp({
    required String email,
    Map<String, dynamic>? metadata,
  }) = AdminSendOtpAuthBody;

  factory AuthBody.adminSignIn({
    required String email,
    required String password,
  }) = AdminSignInAuthBody;

  factory AuthBody.adminVerifyOtp({
    required String email,
    required String code,
  }) = AdminVerifyOtpAuthBody;

  final String collection;
  final String type;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'collection': collection, 'type': type};
  }
}

abstract class AdminAuthBody {
  const AdminAuthBody({required this.type});

  final String type;

  String get collection =>
      throw UnimplementedError('$AdminAuthBody does not have a collection');

  @mustCallSuper
  Map<String, dynamic> toJson() => {'type': type};
}

class SendOtpAuthBody extends AuthBody {
  const SendOtpAuthBody({
    required this.email,
    required super.collection,
    this.metadata,
  }) : super(type: _type);

  factory SendOtpAuthBody.fromJson(Map<String, dynamic> json) {
    return SendOtpAuthBody(
      email: json['email'] as String,
      collection: json['collection'] as String,
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

class VerifyOtpAuthBody extends AuthBody {
  const VerifyOtpAuthBody({
    required this.email,
    required this.code,
    required super.collection,
  }) : super(type: _type);

  factory VerifyOtpAuthBody.fromJson(Map<String, dynamic> json) {
    return VerifyOtpAuthBody(
      email: json['email'] as String,
      collection: json['collection'] as String,
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
    required super.collection,
    required this.email,
    required this.password,
  }) : super(type: _type);

  static const _type = 'signIn';

  final String email;
  final String password;

  factory SignInAuthBody.fromJson(Map<String, dynamic> json) {
    return SignInAuthBody(
      collection: json['collection'] as String,
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
    required super.collection,
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
      collection: json['collection'] as String,
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
