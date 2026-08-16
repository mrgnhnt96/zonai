/// Why FCM will never accept this token again.
///
/// Only these prune. Everything else is a [PushTransientlyFailed], because a
/// token that timed out is not a token that is dead, and collapsing those two
/// is the mistake this feature exists to avoid making on the app's behalf.
enum PushRejectionReason {
  /// The app was uninstalled, or the registration was rotated by the device.
  unregistered,

  /// FCM rejected the token itself as malformed.
  invalidArgument;

  String toJson() => name;

  static PushRejectionReason fromJson(String value) =>
      PushRejectionReason.values.byName(value);
}

/// What happened when one token was sent one message.
///
/// Sealed rather than an enum with a nullable reason, so a consumer that
/// handles delivery and permanent rejection but forgets transient failure
/// fails to compile instead of silently treating a timeout as a success.
sealed class PushOutcome {
  const PushOutcome({required this.token});

  factory PushOutcome.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      PushDelivered._type => PushDelivered(token: json['token'] as String),
      PushPermanentlyRejected._type => PushPermanentlyRejected(
        token: json['token'] as String,
        reason: PushRejectionReason.fromJson(json['reason'] as String),
        detail: json['detail'] as String?,
      ),
      PushTransientlyFailed._type => PushTransientlyFailed(
        token: json['token'] as String,
        detail: json['detail'] as String,
      ),
      final type => throw ArgumentError.value(
        type,
        'type',
        'Invalid push outcome type',
      ),
    };
  }

  final String token;

  Map<String, dynamic> toJson();
}

/// FCM accepted the message for this token. Not a delivery receipt — FCM
/// does not offer one, and `docs/push.md` says so where someone would assume
/// otherwise.
final class PushDelivered extends PushOutcome {
  const PushDelivered({required super.token});

  static const _type = 'delivered';

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'token': token};
}

/// FCM will never accept this token again. The `onPushRejected` hook fires,
/// and then the token is pruned according to `PushConfig`.
final class PushPermanentlyRejected extends PushOutcome {
  const PushPermanentlyRejected({
    required super.token,
    required this.reason,
    this.detail,
  });

  final PushRejectionReason reason;

  /// What the provider actually said, in its own words.
  ///
  /// [reason] has two values because two is all the *fan-out* needs: prune, or
  /// prune. But the two are reached from provider reasons that mean very
  /// different things to a person, and collapsing them loses the difference at
  /// the courier boundary where it is still known. APNs answers `Unregistered`
  /// for an app that was uninstalled and `BadDeviceToken` for a token that is
  /// perfectly valid but was issued by the *other* environment — a sandbox
  /// build's token sent to production, or the reverse (see `ApnsConfig.useSandbox`).
  /// Both map to [PushRejectionReason.unregistered] and both prune correctly;
  /// only the first is a device that is really gone, and only the second is a
  /// deployment mistake somebody can fix. An operator told "rejected" cannot
  /// tell which they are looking at.
  ///
  /// Nullable, and never load-bearing: nothing branches on it, the fan-out does
  /// not read it, and a courier that does not set it is not wrong. It exists so
  /// the string survives as far as a human.
  final String? detail;

  static const _type = 'permanently_rejected';

  @override
  Map<String, dynamic> toJson() => {
    'type': _type,
    'token': token,
    'reason': reason.toJson(),
    'detail': ?detail,
  };
}

/// A timeout, a `5xx`, `UNAVAILABLE`, or a quota rejection. Counted and
/// retried within the job's backoff. Never pruned.
final class PushTransientlyFailed extends PushOutcome {
  const PushTransientlyFailed({required super.token, required this.detail});

  /// What the transport reported, verbatim enough to diagnose from the job
  /// row without turning on debug logging.
  final String detail;

  static const _type = 'transiently_failed';

  @override
  Map<String, dynamic> toJson() => {
    'type': _type,
    'token': token,
    'detail': detail,
  };
}
