import 'package:meta/meta.dart';

/// Where a table's pull stopped: an opaque, server-ordered position.
///
/// Ordering comes ONLY from values the server assigns. On zonai builds with a
/// sequence column that is [seq]; otherwise it is the keyset
/// `(updatedAt, id)` — the id breaks ties between rows the server stamped in
/// the same millisecond, which a bare timestamp cursor silently skips.
@immutable
final class SyncCursor {
  const SyncCursor({required this.updatedAt, required this.id, this.seq});

  factory SyncCursor.fromJson(Map<String, Object?> json) => SyncCursor(
    updatedAt: json['updatedAt']! as int,
    id: json['id']! as String,
    seq: json['seq'] as int?,
  );

  /// Server wall-clock milliseconds of the last row applied.
  final int updatedAt;
  final String id;

  /// Server sequence of the last row applied, when the server provides one.
  final int? seq;

  Map<String, Object?> toJson() => {
    'updatedAt': updatedAt,
    'id': id,
    if (seq != null) 'seq': seq,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncCursor &&
      other.updatedAt == updatedAt &&
      other.id == id &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(updatedAt, id, seq);

  @override
  String toString() =>
      'SyncCursor($updatedAt, $id${seq == null ? '' : ', #$seq'})';
}
