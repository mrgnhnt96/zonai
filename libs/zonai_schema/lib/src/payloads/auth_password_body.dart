import 'package:meta/meta.dart';

sealed class AuthBody {
  const AuthBody({required this.collection, required this.type});

  factory AuthBody.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      SignInAuthBody._type => SignInAuthBody.fromJson(json),
      SignUpAuthBody._type => SignUpAuthBody.fromJson(json),
      AdminSignInAuthBody._type => AdminSignInAuthBody.fromJson(json),
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

  final String collection;
  final String type;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'collection': collection, 'type': type};
  }
}

class AdminSignInAuthBody implements SignInAuthBody {
  const AdminSignInAuthBody({required this.email, required this.password});

  static const _type = 'adminSignIn';

  final String email;
  final String password;
  String get type => _type;

  factory AdminSignInAuthBody.fromJson(Map<String, dynamic> json) {
    return AdminSignInAuthBody(
      email: json['email'] as String,
      password: json['password'] as String,
    );
  }

  Never get collection => throw UnimplementedError(
    'AdminSignInAuthBody does not have a collection',
  );

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'email': email, 'password': password};
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
