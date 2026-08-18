/// `web/llms.txt` is a HAND-MAINTAINED index — nothing generates it.
///
/// That is the whole reason this file exists. `search-index.json` and
/// `sitemap.xml` are regenerated wholesale from `content/`, so a new page
/// cannot ship missing from them. `llms.txt` is curated prose with grouped
/// links, which is what makes it useful to an agent and also what makes it
/// silently drift: a page ships, the index is not touched, and nothing says so.
///
/// Measured when this test was written (2026-08-17): 96 pages, 90 indexed,
/// 7 pages missing — every one of them a feature that shipped and never got
/// indexed. The typed client was about to be the eighth.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_docs/src/navigation.dart';

/// Pages knowingly absent from `llms.txt`.
///
/// This is a RATCHET, not a blessing. Every entry is pre-existing drift found
/// when this test was added, left listed rather than silently indexed because
/// writing another feature's index entry is that feature's call, not this
/// test's. Deleting an entry here (by adding the page to `llms.txt`) is always
/// correct; adding one should need a reason.
const preExistingGaps = <String>{
  '/authentication/external-idp',
  '/authentication/external-idp-supabase',
  '/authentication/oauth',
  '/cli/ping',
  '/dashboard/branding',
  '/extensions/side-effects-push',
  '/operations/views',
};

/// URLs in `llms.txt` that are deliberately not content pages.
const nonPageUrls = <String>{
  '/search-index.json',
  '/llms.txt',
  '/',
};

void main() {
  late String llms;

  setUpAll(() => llms = File('web/llms.txt').readAsStringSync());

  test('every sidebar page is indexed, or listed as a known gap', () {
    final missing = [
      for (final item in flatNavigation)
        if (!llms.contains('https://docs.zonai.dev${item.href}') &&
            !preExistingGaps.contains(item.href) &&
            !nonPageUrls.contains(item.href))
          item.href,
    ];

    expect(
      missing,
      isEmpty,
      reason:
          'These pages are not in web/llms.txt. Add a line for each under the '
          'matching "## " section — agents read this file instead of guessing '
          'APIs, so a page missing here is a page they will not find. If one '
          'genuinely does not belong, add it to preExistingGaps with a reason.',
    );
  });

  test('a known gap that has been fixed is removed from the list', () {
    final fixed = [
      for (final route in preExistingGaps)
        if (llms.contains('https://docs.zonai.dev$route')) route,
    ];

    expect(
      fixed,
      isEmpty,
      reason:
          'These are indexed now — delete them from preExistingGaps. A stale '
          'exemption re-opens the hole it was documenting.',
    );
  });

  test('every indexed URL points at a page that exists', () {
    // Against the filesystem, not the sidebar: `/about` is a real page that is
    // deliberately unlisted, so sidebar membership would fail a live link.
    final urls = RegExp(r'https://docs\.zonai\.dev(/[A-Za-z0-9\-/.]*)')
        .allMatches(llms)
        .map((m) => m.group(1)!)
        .toSet();

    final dead = [
      for (final url in urls)
        if (!nonPageUrls.contains(url) &&
            !File('content$url.md').existsSync())
          url,
    ];

    expect(
      dead,
      isEmpty,
      reason: 'web/llms.txt links a route with no page behind it — renamed or '
          'deleted without the index being updated.',
    );
  });
}
