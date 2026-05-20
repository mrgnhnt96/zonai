part of payloads;

sealed class AuthPayload extends Payload implements JwtPayload {
  const AuthPayload({required this.authType, this.jwt});

  final AuthType authType;
  final String? jwt;
}

class PasswordAuthPayload extends AuthPayload {
  const PasswordAuthPayload({
    required this.email,
    required this.password,
    this.object,
    super.jwt,
  }) : super(authType: .password);

  final String email;
  final String password;
  final Map<String, dynamic>? object;
}

class SignInPasswordAuthPayload extends PasswordAuthPayload {
  const SignInPasswordAuthPayload({
    required super.email,
    required super.password,
  });
}

class SignUpPasswordAuthPayload extends PasswordAuthPayload {
  const SignUpPasswordAuthPayload({
    required super.email,
    required super.password,
    super.object,
    super.jwt,
  });
}

class SendOtpAuthPayload extends AuthPayload {
  const SendOtpAuthPayload({required this.email, this.object, super.jwt})
    : super(authType: .otp);

  final String email;
  final Map<String, dynamic>? object;
}

class VerifyOtpAuthPayload extends AuthPayload {
  const VerifyOtpAuthPayload({required this.email, required this.code, super.jwt})
    : super(authType: .otp);

  final String email;
  final String code;
}
