import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Hook Refusal E2E',
    passwordSecret: fixtureKey('p'),
    jwtSecret: fixtureKey('j'),
    baseUrl: 'http://localhost:8080',
  );
}

/// A fixed, fake key: the alphanumerics in a stride set by [salt], varied
/// enough for `AppConfig.validate`. Built rather than written out, so no
/// secret-shaped literal sits in the repo for a scanner to flag.
String fixtureKey(String salt) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final start = salt.codeUnitAt(0);
  return String.fromCharCodes([
    for (var i = 0; i < 48; i++) chars.codeUnitAt((start + i * 7) % 62),
  ]);
}
