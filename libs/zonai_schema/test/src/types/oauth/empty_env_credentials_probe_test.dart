import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The documented way to supply credentials is
/// `const String.fromEnvironment('GOOGLE_CLIENT_ID')`, which is the empty
/// string when the define is absent — the normal state on a dev machine that
/// has not configured OAuth yet, and the state `apps/playground` is checked in
/// with.
///
/// Whatever the factories do there is the first thing every developer
/// following the docs will hit, so pin it deliberately rather than discovering
/// it from a boot failure.
void main() {
  test('what a built-in factory does with unset --define credentials', () {
    Object? thrown;
    try {
      OAuthProvider.google(
        clientId: const String.fromEnvironment('DEFINITELY_UNSET_CLIENT_ID'),
        clientSecret: const String.fromEnvironment('DEFINITELY_UNSET_SECRET'),
      );
    } on Object catch (e) {
      thrown = e;
    }

    // Recorded, not asserted-as-desired: this test exists to make the
    // behaviour visible and to fail loudly if it silently changes.
    printOnFailure('threw: $thrown');
    expect(
      thrown,
      isA<ArgumentError>(),
      reason:
          'Empty credentials must fail at construction with a clear message, '
          'not at the first sign-in attempt. If this starts passing silently, '
          'a misconfigured project boots and fails later at the provider.',
    );
  });
}
