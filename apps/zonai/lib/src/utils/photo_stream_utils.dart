import 'dart:async';

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

  /// Reads up to [_maxMagicLength] bytes from [source] and returns a stream
  /// that replays those chunks before continuing with the rest of [source].
  static Future<({List<int> prefix, Stream<List<int>> stream})> peekPrefix(
    Stream<List<int>> source,
  ) async {
    final pending = <List<int>>[];
    final prefix = <int>[];
    final iterator = StreamIterator(source);

    while (prefix.length < _maxMagicLength && await iterator.moveNext()) {
      final chunk = iterator.current;
      pending.add(chunk);
      prefix.addAll(chunk);
    }

    Stream<List<int>> replay() async* {
      for (final chunk in pending) {
        yield chunk;
      }
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    }

    return (prefix: prefix, stream: replay());
  }

  /// True when [contentType] names a specific image format (not a generic blob).
  static bool declaresImageMimeType(String? contentType) {
    return ImageMimeType.fromContentType(contentType) != null;
  }

  /// Resolves upload bytes to an [ImageMimeType] and replayable stream.
  ///
  /// When [requiredMimeType] is true and [contentType] is a specific `image/*`
  /// type, magic bytes must match that type. Generic types such as
  /// `application/octet-stream` (per [PhotoCreateMeta] docs) fall back to
  /// detection from file content.
  static Future<(ImageMimeType type, Stream<List<int>> stream)> resolveUploadStream({
    required Stream<List<int>> source,
    required String? contentType,
    required bool requiredMimeType,
  }) async {
    final declared = ImageMimeType.fromContentType(contentType);

    if (requiredMimeType && declared != null) {
      final stream = await verifyExpectedType(source, declared);
      return (declared, stream);
    }

    final (detected, stream) = await detectMimeType(source);
    if (detected == null) {
      throw StateError(
        requiredMimeType && !declaresImageMimeType(contentType)
            ? 'Invalid content type: $contentType'
            : 'Could not detect image type from stream',
      );
    }

    return (detected, stream);
  }

  /// Detects the image format from magic bytes at the start of [source].
  ///
  /// Returns a replay stream that includes the peeked prefix.
  static Future<(ImageMimeType?, Stream<List<int>>)> detectMimeType(
    Stream<List<int>> source,
  ) async {
    final peek = await peekPrefix(source);
    final detected = peek.prefix.isEmpty
        ? null
        : ImageMimeType.detect(peek.prefix);
    return (detected, peek.stream);
  }

  /// Verifies [expected] matches the leading bytes of [source].
  ///
  /// Returns a replay stream that includes the peeked prefix.
  static Future<Stream<List<int>>> verifyExpectedType(
    Stream<List<int>> source,
    ImageMimeType expected,
  ) async {
    final peek = await peekPrefix(source);
    if (peek.prefix.isEmpty) {
      throw StateError('Empty image stream');
    }

    _verifyBuffer(peek.prefix, expected);
    return peek.stream;
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

  /// Applies [maxBytes] when set; otherwise returns [image] unchanged.
  static Stream<List<int>> limitedPhotoImageStream({
    required Stream<List<int>> image,
    required int? maxBytes,
  }) {
    return switch (maxBytes) {
      null => image,
      final limit => limitBytes(image, limit),
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
