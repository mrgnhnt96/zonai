import 'dart:convert';

import 'package:zonai_schema/src/types/id.dart';

/// One notification, as it will be handed to every recipient of a fan-out.
///
/// Serializable because it crosses the worker/host boundary: an app author
/// builds it inside an extension hook, and the fan-out that sends it runs in
/// the host process.
class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    this.collapseKey,
    this.data = const {},
  });

  factory PushMessage.fromJson(Map<String, dynamic> json) => PushMessage(
    title: json['title'] as String,
    body: json['body'] as String,
    collapseKey: json['collapseKey'] as String?,
    data: switch (json['data']) {
      null => const {},
      final Map map => {
        for (final entry in map.entries)
          entry.key.toString(): entry.value as String,
      },
      final value => throw ArgumentError.value(
        value,
        'data',
        'Expected a map of string to string',
      ),
    },
  );

  final String title;
  final String body;

  /// Replaces an earlier undelivered notification carrying the same key
  /// instead of stacking beside it (`collapseKey` on Android,
  /// `apns-collapse-id` on iOS).
  ///
  /// The fan-out is at-least-once (see `docs/push.md`), so a crash can
  /// re-send a batch that already went out. A collapse key is the only
  /// mechanism that makes that duplicate invisible on the device rather than
  /// merely rare, and it is worth setting on anything sent from a fan-out.
  final String? collapseKey;

  /// FCM's `data` payload. Values are strings because FCM's are: typing this
  /// as `Map<String, Object?>` would invite a silent `toString()` at the
  /// transport, and a number that arrives as `"1"` on the device is a bug
  /// nobody can see from here.
  final Map<String, String> data;

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'collapseKey': ?collapseKey,
    'data': data,
  };

  /// FCM's documented ceiling for a message payload.
  ///
  /// Not verified against a live endpoint — it is a documented figure, and
  /// the reason the check below leaves headroom rather than sitting exactly
  /// on it.
  static const maxPayloadBytes = 4096;

  /// Room left for the parts the transport adds per recipient: the
  /// registration token (~163 bytes), the platform blocks a collapse key
  /// expands into, and the JSON envelope around all of it.
  static const _transportOverheadAllowance = 512;

  /// Why this message is too large to send, or null when it fits.
  ///
  /// Checked at enqueue rather than at send, and that is the whole point.
  /// FCM rejects an over-limit payload with `INVALID_ARGUMENT` — the same
  /// status it uses for a dead token — so an oversized message arrives
  /// looking exactly like every recipient's registration going bad at once.
  /// Catching it here means the author is told at the call site, before a
  /// job exists.
  String? get tooLargeReason {
    final size = utf8.encode(jsonEncode(toJson())).length;
    final budget = maxPayloadBytes - _transportOverheadAllowance;
    if (size <= budget) return null;

    return 'PushMessage is $size bytes, over the $budget-byte budget '
        '(FCM allows $maxPayloadBytes including the per-recipient token and '
        'envelope). Shorten the body or move detail into the app: a '
        'notification body is truncated on screen well before this anyway.';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PushMessage) return false;
    if (other.title != title ||
        other.body != body ||
        other.collapseKey != collapseKey ||
        other.data.length != data.length) {
      return false;
    }
    for (final entry in data.entries) {
      if (other.data[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    title,
    body,
    collapseKey,
    Object.hashAllUnordered([
      for (final entry in data.entries) Object.hash(entry.key, entry.value),
    ]),
  );
}

/// Identifies one fan-out job, as returned by `push`.
///
/// The id resolves as soon as the job is durably recorded — not when it has
/// been delivered, and not when it has finished. Query the `_push_jobs`
/// collection with it for progress, counts and failure reasons.
class PushJobId implements Id {
  PushJobId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  factory PushJobId.fromJson(String value) => PushJobId(value);

  static PushJobId generate() => PushJobId(Id.generate(_suffix));

  static const _suffix = 'pj';

  String toJson() => value;

  @override
  final String value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
