/// Where photo bytes live.
///
/// Every photo read and write goes through this, so the engine never touches
/// a file path directly. A photo is named by its key: the `path` column of its
/// `_photos` row, such as `posts/<id>.jpg`, relative to the storage root.
///
/// Brand assets that share the images directory (the favicon and logo) are
/// not photos and are not read or written through this.
abstract class PhotoStorage {
  const PhotoStorage();

  /// Writes [bytes] to [key], replacing anything already there.
  ///
  /// When [bytes] errors, the error is rethrown once the write is closed. What
  /// was written before the error may be left at [key]; the caller deletes it.
  Future<void> write(String key, Stream<List<int>> bytes);

  /// The bytes stored at [key].
  Stream<List<int>> openRead(String key);

  /// Size and modification time of [key], or `null` when nothing is stored
  /// there.
  Future<StoredPhoto?> stat(String key);

  /// Whether anything is stored at [key].
  Future<bool> exists(String key);

  /// Deletes [key]. Does nothing when nothing is stored there.
  Future<void> delete(String key);

  /// Moves what is stored at [from] to [to], replacing anything at [to].
  Future<void> rename(String from, String to);

  /// Everything stored, in no particular order.
  ///
  /// Entries that cannot be read are skipped rather than failing the listing,
  /// so a report built from this under-counts instead of throwing.
  Stream<StoredPhoto> list();

  /// Total bytes and number of entries in [list].
  Future<PhotoStorageUsage> usage() async {
    var bytes = 0;
    var count = 0;
    await for (final photo in list()) {
      bytes += photo.size;
      count++;
    }
    return (bytes: bytes, count: count);
  }
}

typedef PhotoStorageUsage = ({int bytes, int count});

/// One stored photo, as [PhotoStorage.stat] and [PhotoStorage.list] see it.
final class StoredPhoto {
  const StoredPhoto({
    required this.key,
    required this.size,
    required this.modified,
    this.etag,
  });

  final String key;
  final int size;
  final DateTime modified;

  /// The backend's own tag for these exact bytes, unquoted, when it keeps
  /// one.
  ///
  /// A bucket's `LastModified` only has second precision, so a photo replaced
  /// within the same second would keep its size-and-time tag; the bucket's
  /// ETag changes with the bytes.
  final String? etag;
}
