class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  factory AuthSession.fromJson(Map<String, Object?> json) => AuthSession(
    accessToken: json['accessToken'] as String,
    user: (json['user'] as Map).cast<String, Object?>(),
  );

  final String accessToken;
  final Map<String, Object?> user;

  Map<String, Object?> toJson() => {'accessToken': accessToken, 'user': user};
}
