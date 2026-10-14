import '../../deps/args.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/settings.dart';
import '../../deps/zonai_db.dart';
import '../../domain/photo_storage/bucket_photo_storage.dart';
import '../../domain/photo_storage/copy_photos.dart';
import '../../domain/photo_storage/disk_photo_storage.dart';
import '../../utils/format_bytes.dart';

const _usage = '''
Usage: zonai db migrate-photos [options]

Copy every photo under the images directory into the S3-compatible bucket
that PhotosConfig.storage selects. Set S3_ACCESS_KEY_ID and
S3_SECRET_ACCESS_KEY first, as the server needs.

Photos the bucket already holds at the same size are skipped, so the command
can be run again after an interruption, or after the switch to pick up photos
uploaded in between. Each upload is checked against the bucket's size for it.
Local files are kept unless --delete-local is passed.

Options:
  -h, --help          Show help information
  -n, --dry-run       List what would be copied and change nothing
      --delete-local  Delete each local photo once the bucket is verified to
                      hold it
''';

Future<int> migratePhotos() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final dryRun = args.getOrNull<bool>('dry-run', abbr: 'n') == true;
  final deleteLocal = args.getOrNull<bool>('delete-local') == true;

  final target = await zonaiDB.resolvePhotoStorage();
  if (target is! BucketPhotoStorage) {
    logger.error(
      'PhotosConfig.storage is local, so there is no bucket to copy into. '
      'Set it to S3PhotoStorage in your config first.',
    );
    return 1;
  }

  final source = DiskPhotoStorage(fs: fs, root: settings.imagesPath);

  logger.info(
    '${dryRun ? 'Dry run: ' : ''}copying photos from ${settings.imagesPath} '
    'to bucket "${target.bucket}"',
  );

  final summary = await copyPhotos(
    source: source,
    target: target,
    dryRun: dryRun,
    deleteSource: deleteLocal,
    onProgress: (progress) {
      final PhotoCopyProgress(:index, :total, :photo, :outcome) = progress;
      final line =
          '[$index/$total] ${photo.key} (${formatBytes(photo.size)}) '
          '${switch (outcome) {
            PhotoCopyOutcome.copied => 'copied',
            PhotoCopyOutcome.alreadyThere => 'already in bucket',
            PhotoCopyOutcome.wouldCopy => 'would copy',
            PhotoCopyOutcome.failed => 'FAILED: ${progress.error}',
          }}'
          '${progress.deletedSource ? ', local file deleted' : ''}';

      if (outcome == PhotoCopyOutcome.failed) {
        logger.error(line);
      } else {
        logger.info(line);
      }
    },
  );

  logger.info(
    [
      if (dryRun)
        'Would copy ${summary.wouldCopy} (${formatBytes(summary.bytes)})'
      else
        'Copied ${summary.copied} (${formatBytes(summary.bytes)})',
      '${summary.alreadyThere} already in bucket',
      if (deleteLocal && !dryRun) '${summary.deleted} local deleted',
      if (summary.failed > 0) '${summary.failed} failed',
    ].join(', '),
  );

  if (summary.failed > 0) {
    logger.error(
      'Some photos were not copied. Run the command again to retry.',
    );
    return 1;
  }
  return 0;
}
