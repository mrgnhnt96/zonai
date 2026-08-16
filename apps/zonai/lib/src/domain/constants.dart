import 'dart:io' show Platform;

import 'package:meta/meta.dart';

/// Whether zonai is compiled and is in use by a developer
const kIsCompiled = bool.fromEnvironment('__ZONAI_COMPILED__');

/// Environment variable that turns on predictable auth challenges.
const kInsecureTestModeVariable = 'ZONAI_INSECURE_TEST_MODE';

/// The fixed OTP / link secrets handed out under [kInsecureTestMode].
///
/// One constant each so the values live in exactly one place and are trivially
/// greppable, rather than being spelled out at four call sites where the next
/// reader has to notice they are literals.
const kInsecureTestOtp = '123456';
const kInsecureTestMagicLinkSecret = 'dev-magic-link';
const kInsecureTestResetPasswordSecret = 'dev-reset-password';
const kInsecureTestVerifyEmailSecret = 'dev-verify-email';

/// Whether predictable auth challenges are enabled for this process.
///
/// These used to be keyed on [kIsCompiled], which asks "was this built with
/// `dart compile exe`" -- a question about the *build*, not about whether the
/// process is exposed. Anything running from source or on the VM (a container
/// that runs `dart run`, a `dart:test` harness against a real server, a
/// staging box that skipped the compile step) therefore accepted `123456` as
/// the OTP for any address, i.e. account takeover by knowing an email.
///
/// Read from the environment at runtime rather than from a `-D` define: a
/// define is baked into the artifact, so the property could not be turned off
/// without a rebuild, and a binary built once with it on would carry the
/// backdoor forever.
///
/// `zonai serve` refuses to start while this is set (see `serve.dart`), so it
/// cannot be turned on for anything reachable.
bool get kInsecureTestMode =>
    debugInsecureTestMode ??
    insecureTestModeFromEnvironment(Platform.environment);

/// Forces [kInsecureTestMode] on or off. `null` reads the environment.
///
/// Dart cannot mutate its own `Platform.environment`, so in-process tests have
/// no other way to exercise both branches of a runtime env check.
@visibleForTesting
bool? debugInsecureTestMode;

/// Set, non-empty, and not an explicit off value.
///
/// Accepting `0`/`false` as off matters because a deployment tool that sets
/// every known flag to `false` would otherwise switch the backdoor *on*.
bool insecureTestModeFromEnvironment(Map<String, String> environment) {
  final value = environment[kInsecureTestModeVariable]?.trim().toLowerCase();
  return value != null &&
      value.isNotEmpty &&
      value != '0' &&
      value != 'false' &&
      value != 'no' &&
      value != 'off';
}

/// SQLite schema name the log database is attached under.
///
/// `_log` is deliberately *not* qualified with this at the call sites that
/// read it -- an unqualified name resolves into an attached database when
/// `main` has none by that name, so the dashboard's raw `FROM "_log"`, the
/// table API and the retention crons all keep working untouched. The name is
/// needed only where a statement has to say *which file* it means: the
/// attach itself, `VACUUM`, `wal_checkpoint`, and the DDL that creates the
/// table there in the first place.
const kLogDbSchema = 'logdb';

/// SQLite schema name the rate-limit database is attached under.
///
/// Same reasoning as [kLogDbSchema], for the same reason: `_rate_limit` is
/// disposable. Every request that reaches a limited operation reads it and
/// writes it, so on the shared file that churn lands in the application
/// database's WAL and competes with real writes for it -- for rows whose
/// entire lifetime is one rate-limit window and which nobody would want back
/// after a crash.
const kRateLimitDbSchema = 'ratedb';
