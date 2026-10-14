import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/photo_view.dart';
import 'package:zonai_server/src/handlers/photo_handler.dart';

import '../routes/controllers/photos_controller.dart';

/// `GET /img/:id` carries an ETag and a Cache-Control that a shared cache
/// cannot use to get around the photo rules, and answers a matching
/// `If-None-Match` with a bodiless 304.
///
/// Driven through [PhotosController] with a stub [ZonaiDb] that serves real
/// files, so the ETag comes from the same stat the engine uses. Whether a
/// photo is publicly viewable is the engine's call and is covered next to
/// it; here it is an input.
void main() {
  late Directory tmp;
  late File image;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('photo_cache_headers_');
    image = File('${tmp.path}/photo.png')..writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<({ResponseImpl response, List<int> body})> view({
    required bool publiclyViewable,
    String? ifNoneMatch,
    PhotoRedirect? redirect,
  }) {
    return runScoped(
      () async {
        final response = ResponseImpl(requestHeaders: HeadersImpl());
        final stream = await PhotosController(photoHandler: PhotoHandler())
            .view(
              authorization: 'Bearer token',
              id: 'photo-id',
              ifNoneMatch: ifNoneMatch,
              response: response,
            );
        final body = [for (final chunk in await stream.toList()) ...chunk];
        return (response: response, body: body);
      },
      values: {
        fsProvider,
        zonaiDbProvider.overrideWith(
          () =>
              () => _StubZonaiDb(
                image: image.path,
                publiclyViewable: publiclyViewable,
                redirect: redirect,
              ),
        ),
      },
    );
  }

  String currentEtag() {
    final stat = image.statSync();
    return photoEtag(size: stat.size, modified: stat.modified);
  }

  group('200', () {
    test('sends the bytes with a strong ETag and public, no-cache', () async {
      final (:response, :body) = await view(publiclyViewable: true);

      expect(response.statusCode, HttpStatus.ok);
      expect(body, [1, 2, 3, 4]);
      final etag = response.headers.get(HttpHeaders.etagHeader);
      expect(etag, currentEtag());
      expect(etag, isNot(startsWith('W/')), reason: 'the tag is strong');
      expect(
        response.headers.get(HttpHeaders.cacheControlHeader),
        'public, no-cache',
      );
    });

    test('marks a photo an anonymous caller cannot view private', () async {
      final (:response, body: _) = await view(publiclyViewable: false);

      expect(
        response.headers.get(HttpHeaders.cacheControlHeader),
        'private, no-cache',
        reason:
            'a shared cache that stored this could hand it to callers the '
            'canView rules refuse',
      );
    });

    test('never lets a cache skip revalidation', () async {
      for (final publiclyViewable in [true, false]) {
        final (:response, body: _) = await view(
          publiclyViewable: publiclyViewable,
        );
        final cacheControl = response.headers.get(
          HttpHeaders.cacheControlHeader,
        )!;

        // PATCH keeps the URL, so anything that lets a cache reuse a stored
        // copy without asking would serve the old image after a replace.
        expect(cacheControl, contains('no-cache'));
        expect(cacheControl, isNot(contains('immutable')));
        expect(cacheControl, isNot(contains('max-age')));
      }
    });

    test('answers 200 when If-None-Match names another version', () async {
      final (:response, :body) = await view(
        publiclyViewable: true,
        ifNoneMatch: '"0-0"',
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(body, [1, 2, 3, 4]);
    });

    test('the ETag changes when the file behind the id is replaced', () async {
      final (response: before, body: _) = await view(publiclyViewable: true);
      final staleEtag = before.headers.get(HttpHeaders.etagHeader)!;

      // What PATCH does: new bytes behind the same id.
      image
        ..writeAsBytesSync([9, 9, 9, 9, 9])
        ..setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));

      final (:response, :body) = await view(
        publiclyViewable: true,
        ifNoneMatch: staleEtag,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(body, [9, 9, 9, 9, 9]);
      expect(response.headers.get(HttpHeaders.etagHeader), isNot(staleEtag));
    });
  });

  group('304', () {
    for (final (name, header) in [
      ('the exact tag', null),
      ('the tag with a W/ prefix', 'W/'),
      ('the tag inside a list', '"other", '),
    ]) {
      test('when If-None-Match carries $name', () async {
        final etag = currentEtag();
        final ifNoneMatch = switch (header) {
          null => etag,
          final prefix => '$prefix$etag',
        };

        final (:response, :body) = await view(
          publiclyViewable: false,
          ifNoneMatch: ifNoneMatch,
        );

        expect(response.statusCode, HttpStatus.notModified);
        expect(body, isEmpty);
        expect(response.headers.get(HttpHeaders.etagHeader), etag);
        expect(
          response.headers.get(HttpHeaders.cacheControlHeader),
          'private, no-cache',
          reason: 'a 304 refreshes the stored headers, so it repeats them',
        );
      });
    }

    test('when If-None-Match is *', () async {
      final (:response, :body) = await view(
        publiclyViewable: true,
        ifNoneMatch: '*',
      );

      expect(response.statusCode, HttpStatus.notModified);
      expect(body, isEmpty);
    });
  });

  group('302', () {
    final public = PhotoRedirect.public(
      Uri.parse('https://img.example.com/posts/a.png?v=1'),
    );
    final presigned = PhotoRedirect.presigned(
      Uri.parse(
        'https://bucket.example.com/photos/posts/a.png?X-Amz-Signature=s',
      ),
    );

    test('to the public URL, cached like the photo itself', () async {
      final (:response, :body) = await view(
        publiclyViewable: true,
        redirect: public,
      );

      expect(response.statusCode, HttpStatus.found);
      expect(body, isEmpty);
      expect(
        response.headers.get(HttpHeaders.locationHeader),
        public.location.toString(),
      );
      expect(response.headers.get(HttpHeaders.etagHeader), currentEtag());
      expect(
        response.headers.get(HttpHeaders.cacheControlHeader),
        'public, no-cache',
      );
    });

    test('to the public URL answers 304 when the tag still matches', () async {
      final (:response, :body) = await view(
        publiclyViewable: true,
        redirect: public,
        ifNoneMatch: currentEtag(),
      );

      expect(response.statusCode, HttpStatus.notModified);
      expect(body, isEmpty);
      expect(response.headers.get(HttpHeaders.locationHeader), isNull);
    });

    test('to a presigned URL, which no cache may keep', () async {
      final (:response, :body) = await view(
        publiclyViewable: false,
        redirect: presigned,
        // Even a matching tag is ignored: a 304 would let a cache keep
        // reusing a redirect it stored, past the rules and the expiry.
        ifNoneMatch: currentEtag(),
      );

      expect(response.statusCode, HttpStatus.found);
      expect(body, isEmpty);
      expect(
        response.headers.get(HttpHeaders.locationHeader),
        presigned.location.toString(),
      );
      expect(
        response.headers.get(HttpHeaders.cacheControlHeader),
        'private, no-store',
        reason: 'the link grants access by itself',
      );
      expect(response.headers.get(HttpHeaders.etagHeader), isNull);
    });
  });

  group('etagMatches', () {
    test('ignores surrounding whitespace and W/ on the stored side', () {
      expect(etagMatches('  "a-b" ', 'W/"a-b"'), isTrue);
    });

    test('does not match a different tag', () {
      expect(etagMatches('"a-b", "c-d"', '"a-c"'), isFalse);
    });
  });
}

/// A [ZonaiDb] that serves one file from disk with a fixed visibility.
class _StubZonaiDb implements ZonaiDb {
  _StubZonaiDb({
    required this.image,
    required this.publiclyViewable,
    this.redirect,
  });

  final String image;
  final bool publiclyViewable;
  final PhotoRedirect? redirect;

  @override
  Future<PhotoView> viewPhoto(String id, {required String? token}) async {
    final view = PhotoView.forFile(
      fs.file(image),
      publiclyViewable: publiclyViewable,
    );
    return switch (redirect) {
      null => view,
      final redirect => view.redirectTo(redirect),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
