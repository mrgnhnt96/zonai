import 'package:path/path.dart' as p;
import 'package:zonai/src/domain/photo_storage/photo_storage.dart';
import 'package:zonai_schema/zonai_schema.dart' show ImageMimeType;

/// What [copyPhotos] did with one photo.
enum PhotoCopyOutcome {
  /// Uploaded, and the target reported the same size afterwards.
  copied,

  /// The target already held an object of the same size, so nothing was sent.
  /// This is what makes a re-run after an interruption cheap.
  alreadyThere,

  /// A dry run that would have uploaded it.
  wouldCopy,

  /// The upload or its size check failed; see [PhotoCopyProgress.error].
  failed,
}

/// One photo [copyPhotos] has finished with, reported as it goes.
final class PhotoCopyProgress {
  const PhotoCopyProgress({
    required this.index,
    required this.total,
    required this.photo,
    required this.outcome,
    this.deletedSource = false,
    this.error,
  });

  /// 1-based position of [photo] among [total].
  final int index;
  final int total;
  final StoredPhoto photo;
  final PhotoCopyOutcome outcome;

  /// Whether the source file was deleted after the target was verified.
  final bool deletedSource;
  final Object? error;
}

typedef PhotoCopySummary = ({
  int copied,
  int alreadyThere,
  int wouldCopy,
  int failed,
  int deleted,
  int bytes,
});

/// Whether [key] names a photo rather than something else kept in the images
/// directory.
///
/// Photos are always `<table>/<id>.<ext>` with an image extension. The brand
/// assets (`favicon.ico`, `logo.png`) sit at the top level and are read off
/// disk by the server, never through `PhotoStorage`; an update's leftover
/// `<key>.tmp` is not a photo either.
bool isPhotoKey(String key) {
  final parts = p.split(key);
  if (parts.length < 2) return false;

  final extension = p.extension(key);
  if (extension.length < 2) return false;
  return ImageMimeType.fromFileExtension(extension.substring(1)) != null;
}

/// Copies every photo in [source] to [target].
///
/// A photo the target already holds at the same size is skipped, so running
/// this again after an interruption only sends what is missing. After each
/// upload the target is asked for the object's size, and a mismatch counts as
/// a failure. One failure does not stop the rest.
///
/// [dryRun] reports what would be sent and changes nothing. [deleteSource]
/// deletes each source file once the target is verified to hold it, whether
/// this run uploaded it or an earlier one did.
Future<PhotoCopySummary> copyPhotos({
  required PhotoStorage source,
  required PhotoStorage target,
  bool dryRun = false,
  bool deleteSource = false,
  void Function(PhotoCopyProgress progress)? onProgress,
}) async {
  final photos =
      await source.list().where((photo) => isPhotoKey(photo.key)).toList()
        ..sort((a, b) => a.key.compareTo(b.key));

  var copied = 0;
  var alreadyThere = 0;
  var wouldCopy = 0;
  var failed = 0;
  var deleted = 0;
  var bytes = 0;

  for (final (i, photo) in photos.indexed) {
    PhotoCopyOutcome outcome;
    Object? error;
    var deletedSource = false;

    try {
      final existing = await target.stat(photo.key);
      if (existing != null && existing.size == photo.size) {
        outcome = PhotoCopyOutcome.alreadyThere;
      } else if (dryRun) {
        outcome = PhotoCopyOutcome.wouldCopy;
      } else {
        await target.write(photo.key, source.openRead(photo.key));

        final uploaded = await target.stat(photo.key);
        if (uploaded?.size != photo.size) {
          throw PhotoCopySizeMismatch(
            key: photo.key,
            expected: photo.size,
            actual: uploaded?.size,
          );
        }
        outcome = PhotoCopyOutcome.copied;
      }

      if (deleteSource && !dryRun && outcome != PhotoCopyOutcome.wouldCopy) {
        await source.delete(photo.key);
        deletedSource = true;
      }
    } catch (e) {
      outcome = PhotoCopyOutcome.failed;
      error = e;
    }

    switch (outcome) {
      case PhotoCopyOutcome.copied:
        copied++;
        bytes += photo.size;
      case PhotoCopyOutcome.alreadyThere:
        alreadyThere++;
      case PhotoCopyOutcome.wouldCopy:
        wouldCopy++;
        bytes += photo.size;
      case PhotoCopyOutcome.failed:
        failed++;
    }
    if (deletedSource) deleted++;

    onProgress?.call(
      PhotoCopyProgress(
        index: i + 1,
        total: photos.length,
        photo: photo,
        outcome: outcome,
        deletedSource: deletedSource,
        error: error,
      ),
    );
  }

  return (
    copied: copied,
    alreadyThere: alreadyThere,
    wouldCopy: wouldCopy,
    failed: failed,
    deleted: deleted,
    bytes: bytes,
  );
}

/// The target held a different number of bytes than were sent.
final class PhotoCopySizeMismatch implements Exception {
  const PhotoCopySizeMismatch({
    required this.key,
    required this.expected,
    required this.actual,
  });

  final String key;
  final int expected;

  /// `null` when the target had nothing at [key] after the upload.
  final int? actual;

  @override
  String toString() => switch (actual) {
    null => 'uploaded $key but the bucket has no object there',
    final actual =>
      'uploaded $expected bytes to $key but the bucket has $actual',
  };
}
