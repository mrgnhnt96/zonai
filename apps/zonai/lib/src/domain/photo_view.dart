import 'package:file/file.dart';
import 'package:zonai/src/domain/photo_storage/photo_storage.dart';

/// A photo the caller may view, plus what a response needs to cache it.
class PhotoView {
  const PhotoView({
    required this.extension,
    required this.etag,
    required this.publiclyViewable,
    required Stream<List<int>> Function() openRead,
    this.redirect,
  }) : _openRead = openRead;

  /// Builds the view for [photo] as [storage] holds it.
  ///
  /// [etag] is the storage's own tag when it has one ([StoredPhoto.etag]),
  /// otherwise derived from size and modification time.
  factory PhotoView.stored(
    PhotoStorage storage,
    StoredPhoto photo, {
    required bool publiclyViewable,
  }) {
    return PhotoView(
      extension: photo.key.split('.').last,
      etag: switch (photo.etag) {
        final etag? => '"${etag.replaceAll('"', '')}"',
        null => photoEtag(size: photo.size, modified: photo.modified),
      },
      publiclyViewable: publiclyViewable,
      openRead: () => storage.openRead(photo.key),
    );
  }

  /// Builds the view for [file], deriving [etag] from its current size and
  /// modification time.
  factory PhotoView.forFile(File file, {required bool publiclyViewable}) {
    final stat = file.statSync();
    return PhotoView(
      extension: file.path.split('.').last,
      etag: photoEtag(size: stat.size, modified: stat.modified),
      publiclyViewable: publiclyViewable,
      openRead: file.openRead,
    );
  }

  /// The stored file extension, such as `jpg`, which names the image type.
  final String extension;

  /// A strong entity tag, quoted, ready for the `ETag` header.
  final String etag;

  /// Whether a caller with no JWT would also pass the `_photos` table and row
  /// `canView` rules for this photo.
  ///
  /// Decides `public` versus `private` in `Cache-Control`. A shared cache that
  /// stores a response can serve it to anyone, so only a photo every caller
  /// may see is allowed to be stored there.
  final bool publiclyViewable;

  /// Where to send the caller instead of streaming the bytes, when the
  /// storage serves them itself; `null` to stream.
  final PhotoRedirect? redirect;

  final Stream<List<int>> Function() _openRead;

  /// The photo's bytes.
  Stream<List<int>> openRead() => _openRead();

  /// This view, answered with [redirect] instead of the bytes.
  PhotoView redirectTo(PhotoRedirect redirect) => PhotoView(
    extension: extension,
    etag: etag,
    publiclyViewable: publiclyViewable,
    openRead: _openRead,
    redirect: redirect,
  );
}

/// A URL the photo's bytes can be fetched from directly, which
/// `GET /img/:id` answers with `302 Found` once the photo rules have passed.
final class PhotoRedirect {
  /// A URL anyone may fetch, for a photo a caller with no token could view.
  const PhotoRedirect.public(this.location) : presigned = false;

  /// A URL that carries its own short-lived signature.
  const PhotoRedirect.presigned(this.location) : presigned = true;

  final Uri location;

  /// Whether [location] grants access by itself until it expires.
  ///
  /// Such a redirect must not be stored by any cache: a stored copy would
  /// hand the link to callers the rules never saw, and outlive its expiry.
  final bool presigned;
}

/// A strong ETag from a photo's [size] and [modified] time.
///
/// `PATCH /img/:id` keeps the id and the URL but writes a new file, so the
/// modification time moves and the tag changes with it. Reading the bytes to
/// hash them would cost a full read per request just to answer a 304, which
/// is the request that should be cheapest. The same pair is what nginx and
/// Apache use for their default ETags.
String photoEtag({required int size, required DateTime modified}) =>
    '"${size.toRadixString(16)}-'
    '${modified.microsecondsSinceEpoch.toRadixString(16)}"';
