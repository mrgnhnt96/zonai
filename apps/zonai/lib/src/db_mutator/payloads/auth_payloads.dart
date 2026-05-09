part of payloads;

sealed class AuthPayload extends Payload {
  const AuthPayload();
}

class PasswordAuthPayload extends AuthPayload {
  const PasswordAuthPayload({required this.email, required this.password});

  final String email;
  final String password;
}
