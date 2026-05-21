part of payloads;

sealed class AuthPayload extends Payload implements JwtPayload {
  const AuthPayload({required this.authType, this.jwt});

  final AuthType authType;
  final String? jwt;
}

sealed class VerifyAuthPayload extends Payload implements JwtPayload {
  const VerifyAuthPayload({required this.authType, this.jwt});

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

class VerifyOtpAuthPayload extends VerifyAuthPayload implements AuthPayload {
  const VerifyOtpAuthPayload({
    required this.email,
    required this.code,
    super.jwt,
  }) : super(authType: .otp);

  final String email;
  final String code;
}

class SendMagicLinkAuthPayload extends AuthPayload {
  const SendMagicLinkAuthPayload({required this.email, this.object, super.jwt})
    : super(authType: .magicLink);

  final String email;
  final Map<String, dynamic>? object;
}

class VerifyMagicLinkAuthPayload extends VerifyAuthPayload
    implements AuthPayload {
  const VerifyMagicLinkAuthPayload({required this.secret, super.jwt})
    : super(authType: .magicLink);

  final String secret;
  String get email =>
      throw UnimplementedError('Email is not available in the secret');
}

class ResetPasswordAuthPayload extends AuthPayload {
  const ResetPasswordAuthPayload({required this.email, super.jwt})
    : super(authType: .password);

  final String email;
}

class ConfirmResetPasswordAuthPayload extends VerifyAuthPayload
    implements AuthPayload {
  const ConfirmResetPasswordAuthPayload({
    required this.token,
    required this.newPassword,
    super.jwt,
  }) : super(authType: .password);

  final String token;
  final String newPassword;
}
