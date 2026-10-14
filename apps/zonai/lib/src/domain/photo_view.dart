import 'package:file/file.dart';

/// A photo the caller may view, plus what a response needs to cache it.
class PhotoView {
  const PhotoView({
    required this.file,
    required this.etag,
    required this.publiclyViewable,
  });

  /// Builds the view for [file], deriving [etag] from its current size and
  /// modification time.
  factory PhotoView.forFile(File file, {required bool publiclyViewable}) {
    final stat = file.statSync();
    return PhotoView(
      file: file,
      etag: photoEtag(size: stat.size, modified: stat.modified),
      publiclyViewable: publiclyViewable,
    );
  }

  final File file;

  /// A strong entity tag, quoted, ready for the `ETag` header.
  final String etag;

  /// Whether a caller with no JWT would also pass the `_photos` table and row
  /// `canView` rules for this photo.
  ///
  /// Decides `public` versus `private` in `Cache-Control`. A shared cache that
  /// stores a response can serve it to anyone, so only a photo every caller
  /// may see is allowed to be stored there.
  final bool publiclyViewable;
}

/// A strong ETag from a file's [size] and [modified] time.
///
/// `PATCH /img/:id` keeps the id and the URL but writes a new file, so the
/// modification time moves and the tag changes with it. Reading the bytes to
/// hash them would cost a full read per request just to answer a 304, which
/// is the request that should be cheapest. The same pair is what nginx and
/// Apache use for their default ETags.
String photoEtag({required int size, required DateTime modified}) =>
    '"${size.toRadixString(16)}-'
    '${modified.microsecondsSinceEpoch.toRadixString(16)}"';
