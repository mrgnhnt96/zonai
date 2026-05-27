import 'package:zonai_schema/zonai_schema.dart';

/// Stream helpers for photo uploads (size limits and mime verification).
abstract final class PhotoStreamUtils {
  PhotoStreamUtils._();

  /// Longest magic-byte prefix required to verify any [ImageMimeType].
  static const _maxMagicLength = 12;

  /// Yields chunks from [source] until the cumulative size exceeds [maxBytes].
  ///
  /// Throws [StateError] when the limit is exceeded.
  static Stream<List<int>> limitBytes(
    Stream<List<int>> source,
    int maxBytes,
  ) async* {
    var total = 0;

    await for (final chunk in source) {
      total += chunk.length;
      if (total > maxBytes) {
        throw StateError(
          'Stream exceeds maximum size of $maxBytes bytes (received at least $total)',
        );
      }
      yield chunk;
    }
  }

  /// Yields chunks from [source] after verifying the leading bytes match [expected].
  ///
  /// Throws [StateError] when the stream is empty or the bytes do not match
  /// [expected].
  static Stream<List<int>> verifyMimeType(
    Stream<List<int>> source,
    ImageMimeType expected,
  ) async* {
    final pending = <List<int>>[];
    final buffer = <int>[];
    var verified = false;

    await for (final chunk in source) {
      if (verified) {
        yield chunk;
        continue;
      }

      pending.add(chunk);
      buffer.addAll(chunk);

      if (buffer.length < _maxMagicLength) {
        continue;
      }

      _verifyBuffer(buffer, expected);
      verified = true;
      for (final pendingChunk in pending) {
        yield pendingChunk;
      }
      pending.clear();
      buffer.clear();
    }

    if (verified) {
      return;
    }

    if (buffer.isEmpty) {
      throw StateError('Empty image stream');
    }

    _verifyBuffer(buffer, expected);
    for (final pendingChunk in pending) {
      yield pendingChunk;
    }
  }

  /// Verifies [image] matches [imageType], then optionally enforces [maxBytes].
  static Stream<List<int>> verifiedPhotoImageStream({
    required Stream<List<int>> image,
    required ImageMimeType imageType,
    required int? maxBytes,
  }) {
    var stream = verifyMimeType(image, imageType);
    return switch (maxBytes) {
      null => stream,
      final limit => limitBytes(stream, limit),
    };
  }

  static void _verifyBuffer(List<int> buffer, ImageMimeType expected) {
    if (expected.matchesBytes(buffer)) {
      return;
    }

    final detected = ImageMimeType.detect(buffer);
    throw StateError(
      'Content type mismatch: declared ${expected.mimeType}, '
      'detected ${detected?.mimeType ?? 'unknown'}',
    );
  }
}
