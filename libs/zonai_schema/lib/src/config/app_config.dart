final class AppConfig {
  const AppConfig({required this.passwordPepper, required this.jwtPepper});

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    passwordPepper: json['passwordPepper'] as String,
    jwtPepper: json['jwtPepper'] as String,
  );

  final String passwordPepper;
  final String jwtPepper;

  Map<String, dynamic> toJson() => {
    'passwordPepper': passwordPepper,
    'jwtPepper': jwtPepper,
  };
}
