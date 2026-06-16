import 'package:test/test.dart';
import 'package:zonai_web/server/session_auth.dart';

void main() {
  group('ssrShowsSignedInShell', () {
    test('uses verified session', () {
      expect(
        ssrShowsSignedInShell(const SsrSession(signedIn: true, clearAuthCookie: false), null),
        isTrue,
      );
    });

    test('falls back to cookie when verification is inconclusive', () {
      expect(
        ssrShowsSignedInShell(const SsrSession(signedIn: false, clearAuthCookie: false), 'jwt'),
        isTrue,
      );
    });

    test('does not treat stale cookies as signed in', () {
      expect(
        ssrShowsSignedInShell(const SsrSession(signedIn: false, clearAuthCookie: true), 'jwt'),
        isFalse,
      );
    });

    test('unsigned out with no cookie', () {
      expect(
        ssrShowsSignedInShell(const SsrSession(signedIn: false, clearAuthCookie: false), null),
        isFalse,
      );
    });
  });
}
