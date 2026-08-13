// Arguments inside `AppConfig(...)` -- the `baseUrl: ...`, `email: ...`,
// `photos: ...` lines the configuration pages show one at a time.
//
// The three required arguments are supplied here so a fragment can show only
// the option it is about, which is what the prose around it is doing.
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  // <<body>>
);
