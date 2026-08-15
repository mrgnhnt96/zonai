/// What Zonai does to a row whose token FCM permanently rejected.
///
/// The hook fires under all three, including [none] — that is what makes
/// [none] a usable choice rather than a silent one.
enum OnPermanentRejection {
  /// Set the `deviceToken` column to null. **The default.**
  ///
  /// The failure modes here are not symmetric. Nothing stops an app putting
  /// its token column on `users` rather than a dedicated table, and under a
  /// [deleteRow] default a wiped phone would delete a user account —
  /// unrecoverable, and caused by a setting nobody chose. The worst case here
  /// is a row with a null token, which is inert and cleanable.
  clearColumn,

  /// Delete the whole row. Opt-in, and destructive: read [clearColumn] first.
  deleteRow,

  /// Zonai does nothing. `onPushRejected` is the only signal, and it still
  /// fires.
  none;

  String toJson() => name;

  static OnPermanentRejection fromJson(String value) =>
      OnPermanentRejection.values.byName(value);
}

/// The FCM service account Zonai signs its access tokens with.
///
/// Every other Zonai secret arrives through `String.fromEnvironment` — a
/// compile-time define baked into the worker executables. That is tolerable
/// for an SMTP password and materially worse for a service account, which is
/// an asymmetric **private key**: baking it into a distributed binary means
/// rotation requires a recompile and a redeploy, and the key travels wherever
/// the binary travels.
sealed class PushCredentials {
  const PushCredentials();

  factory PushCredentials.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      PushCredentialsFile._type => PushCredentialsFile(
        json['path'] as String,
      ),
      PushCredentialsInline._type => PushCredentialsInline(
        json['json'] as String,
      ),
      final type => throw ArgumentError.value(
        type,
        'type',
        'Invalid push credentials type',
      ),
    };
  }

  /// Read from disk at runtime. **Recommended for production**: rotation is
  /// replace-the-file-and-restart, and the key never enters the binary.
  const factory PushCredentials.file(String path) = PushCredentialsFile;

  /// A service-account JSON string, typically from `String.fromEnvironment`.
  ///
  /// Convenient for development and for platforms that only offer env
  /// injection. Rotating this form requires a recompile and redeploy.
  const factory PushCredentials.inline(String json) = PushCredentialsInline;

  Map<String, dynamic> toJson();
}

final class PushCredentialsFile extends PushCredentials {
  const PushCredentialsFile(this.path);

  final String path;

  static const _type = 'file';

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'path': path};
}

final class PushCredentialsInline extends PushCredentials {
  const PushCredentialsInline(this.json);

  final String json;

  static const _type = 'inline';

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'json': json};
}

/// Push delivery configuration, per flavor, exactly like `AppConfig.email`.
///
/// A project with no [PushConfig] logs a warning and enqueues nothing. A
/// missing config must never throw; it must be loud.
class PushConfig {
  const PushConfig({
    required this.projectId,
    required this.credentials,
    this.onPermanentRejection = OnPermanentRejection.clearColumn,
    this.batchSize = defaultBatchSize,
    this.concurrency = defaultConcurrency,
    this.maxAttemptsPerBatch = defaultMaxAttemptsPerBatch,
  }) : assert(batchSize > 0, 'batchSize must be positive'),
       assert(concurrency > 0, 'concurrency must be positive'),
       assert(maxAttemptsPerBatch > 0, 'maxAttemptsPerBatch must be positive');

  factory PushConfig.fromJson(Map<String, dynamic> json) => PushConfig(
    projectId: json['projectId'] as String,
    credentials: PushCredentials.fromJson(
      Map<String, dynamic>.from(json['credentials'] as Map),
    ),
    onPermanentRejection: switch (json['onPermanentRejection']) {
      null => OnPermanentRejection.clearColumn,
      final String value => OnPermanentRejection.fromJson(value),
      final value => throw ArgumentError.value(
        value,
        'onPermanentRejection',
        'Expected a string',
      ),
    },
    batchSize: json['batchSize'] as int? ?? defaultBatchSize,
    concurrency: json['concurrency'] as int? ?? defaultConcurrency,
    maxAttemptsPerBatch:
        json['maxAttemptsPerBatch'] as int? ?? defaultMaxAttemptsPerBatch,
  );

  /// Rows read, sent and committed per checkpoint.
  ///
  /// This one number is three things at once: the memory bound on a batch,
  /// the checkpoint granularity, and — because the fan-out is at-least-once —
  /// the blast radius of a crash in duplicate notifications. 500 is a
  /// starting point chosen to be small enough that a crash duplicates a
  /// screenful rather than a mailing list; it is not a measured optimum, and
  /// `docs/push.md` says so.
  static const defaultBatchSize = 500;

  /// Sends in flight at once within a batch.
  ///
  /// Sequential is slow and fully concurrent trips FCM's per-project quota,
  /// which is why this is a bounded pool rather than an unbounded
  /// `Future.wait`. Also unmeasured.
  static const defaultConcurrency = 8;

  /// Attempts a batch's transient failures get before the job gives up on
  /// this pass and leaves the cursor where it is. The next drain resumes
  /// there, so giving up is a pause, not a loss.
  static const defaultMaxAttemptsPerBatch = 3;

  /// The Firebase project the messages are sent through
  /// (`/v1/projects/{projectId}/messages:send`).
  final String projectId;

  final PushCredentials credentials;

  final OnPermanentRejection onPermanentRejection;

  final int batchSize;
  final int concurrency;
  final int maxAttemptsPerBatch;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'credentials': credentials.toJson(),
    'onPermanentRejection': onPermanentRejection.toJson(),
    'batchSize': batchSize,
    'concurrency': concurrency,
    'maxAttemptsPerBatch': maxAttemptsPerBatch,
  };
}
