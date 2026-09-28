/// Which push transport a device token belongs to.
///
/// A token is an opaque string and the two services issue strings that look
/// broadly alike, so nothing about the value itself says which one to send
/// it to. Guessing from its shape is the tempting mistake: it works until an
/// SDK version changes the format, and then it fails silently, per-device,
/// in production.
///
/// So the app says. One row per device, one column holding this, and `push`
/// reads it alongside the token — see `platformColumn`.
enum DevicePlatform {
  /// Delivered through APNs directly when `PushConfig.apns` is set, and
  /// through FCM otherwise. An app can move between the two by changing
  /// config, without touching a token or a row.
  ///
  /// Sent to the host [ApnsConfig.useSandbox] picks — production unless the
  /// server says otherwise.
  ios('ios'),

  /// An iOS device running a **development-signed** build — one installed
  /// from Xcode or `flutter run` rather than TestFlight or the App Store.
  ///
  /// Always sent to `api.sandbox.push.apple.com`, whatever
  /// [ApnsConfig.useSandbox] says, with the same auth key: a `.p8` is valid
  /// in both environments and only the host differs. That is what lets one
  /// deployed server reach a developer's phone and the TestFlight fleet at
  /// once.
  ///
  /// The environment is a fact about how the *build* was signed, which the
  /// app knows at compile time and nothing else can recover — a sandbox
  /// token and a production token are indistinguishable strings. Sent to the
  /// wrong host, a valid token answers `BadDeviceToken`, which reads as a
  /// dead device and is pruned like one.
  ///
  /// APNs only. FCM keeps its own record of the environment, so with no
  /// `PushConfig.apns` a row saying this is unroutable rather than silently
  /// sent through FCM.
  iosSandbox('ios-sandbox'),

  /// Delivered through FCM. There is no direct equivalent — the Android
  /// transport *is* FCM.
  android('android');

  const DevicePlatform(this.wireName);

  /// What is stored in a platform column and sent over the wire.
  final String wireName;

  String toJson() => wireName;

  /// Parses a stored value, case-insensitively.
  ///
  /// Returns null rather than throwing for an unrecognised value: an
  /// unexpected string in one row is that row's problem, and a fan-out must
  /// not fail everyone else's notification over it.
  static DevicePlatform? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final platform in DevicePlatform.values) {
      if (platform.wireName == normalized) return platform;
    }
    // Common aliases, because this column is written by client code that
    // Zonai does not control and `Platform.operatingSystem` on iOS is
    // "ios" but plenty of apps store "iOS" or "apple".
    return switch (normalized) {
      'apple' || 'iphone' || 'ipad' => DevicePlatform.ios,
      'ios_sandbox' || 'iossandbox' => DevicePlatform.iosSandbox,
      _ => null,
    };
  }
}

/// The APNs auth key Zonai signs its provider tokens with.
///
/// Same shape and same reasoning as `PushCredentials`: a `.p8` is an
/// asymmetric **private key**, so baking it into a binary makes rotation a
/// rebuild rather than a file copy.
sealed class ApnsCredentials {
  const ApnsCredentials();

  factory ApnsCredentials.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      ApnsCredentialsFile._type => ApnsCredentialsFile(json['path'] as String),
      ApnsCredentialsInline._type => ApnsCredentialsInline(
        json['pem'] as String,
      ),
      final type => throw ArgumentError.value(
        type,
        'type',
        'Invalid APNs credentials type',
      ),
    };
  }

  /// Read from disk at runtime. **Recommended for production.**
  const factory ApnsCredentials.file(String path) = ApnsCredentialsFile;

  /// The PEM contents, typically from `String.fromEnvironment`.
  const factory ApnsCredentials.inline(String pem) = ApnsCredentialsInline;

  Map<String, dynamic> toJson();
}

final class ApnsCredentialsFile extends ApnsCredentials {
  const ApnsCredentialsFile(this.path);

  static const _type = 'file';

  final String path;

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'path': path};

  @override
  bool operator ==(Object other) =>
      other is ApnsCredentialsFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class ApnsCredentialsInline extends ApnsCredentials {
  const ApnsCredentialsInline(this.pem);

  static const _type = 'inline';

  final String pem;

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'pem': pem};

  @override
  bool operator ==(Object other) =>
      other is ApnsCredentialsInline && other.pem == pem;

  @override
  int get hashCode => pem.hashCode;
}

/// Talking to Apple directly, without Firebase in the path.
///
/// **Why this exists when FCM already reaches iOS.** FCM delivers to iOS by
/// proxying to APNs with an auth key you upload to its console — an upload
/// with no API behind it, so it cannot be scripted, put in Terraform, or done
/// by CI. It also adds a failure mode of its own: when that key lapses, FCM
/// answers `401 UNAUTHENTICATED` / `THIRD_PARTY_AUTH_ERROR`, which is
/// indistinguishable from a bad service account without reading
/// `error.details[]`. Going direct removes both.
///
/// It also makes iOS the *better tested* platform, which is not the usual
/// order. FCM has no sandbox — every address Google publishes reaches a real
/// device — while APNs has `api.sandbox.push.apple.com`, so a real send can
/// be exercised without a real notification.
class ApnsConfig {
  const ApnsConfig({
    required this.credentials,
    required this.keyId,
    required this.teamId,
    required this.bundleId,
    this.useSandbox = false,
  });

  factory ApnsConfig.fromJson(Map<String, dynamic> json) => ApnsConfig(
    credentials: ApnsCredentials.fromJson(
      Map<String, dynamic>.from(json['credentials'] as Map),
    ),
    keyId: json['keyId'] as String,
    teamId: json['teamId'] as String,
    bundleId: json['bundleId'] as String,
    useSandbox: json['useSandbox'] as bool? ?? false,
  );

  final ApnsCredentials credentials;

  /// The 10-character Key ID Apple shows next to the key.
  ///
  /// It travels in the JWT's `kid` header, and it is **not** recoverable from
  /// the `.p8` — the file is an unadorned PKCS#8 key, byte-indistinguishable
  /// from any other, so the only record of which key it is is whatever the
  /// filename says. Pairing a key with the wrong id fails authentication
  /// with no clue as to which half is wrong.
  final String keyId;

  /// The 10-character Team ID, which becomes the JWT's `iss`.
  final String teamId;

  /// The app's bundle identifier, sent as the `apns-topic` header.
  ///
  /// APNs rejects a send without it: one key can serve every app on a team,
  /// so the topic is the only thing saying which app a notification is for.
  final String bundleId;

  /// Send plain `DevicePlatform.ios` recipients to
  /// `api.sandbox.push.apple.com` rather than production.
  ///
  /// The two are separate worlds: a token issued to a development build is
  /// unknown to production and vice versa, and the symptom is `BadDeviceToken`
  /// on a token that is perfectly valid — just not here.
  ///
  /// This is only the *default*. A row stored as `DevicePlatform.iosSandbox`
  /// goes to the sandbox regardless, so one server can serve development and
  /// production builds side by side.
  final bool useSandbox;

  static const productionHost = 'api.push.apple.com';
  static const sandboxHost = 'api.sandbox.push.apple.com';

  String get host => useSandbox ? sandboxHost : productionHost;

  /// This config pointed at the sandbox, same key and same app.
  ApnsConfig get sandbox => useSandbox
      ? this
      : ApnsConfig(
          credentials: credentials,
          keyId: keyId,
          teamId: teamId,
          bundleId: bundleId,
          useSandbox: true,
        );

  Map<String, dynamic> toJson() => {
    'credentials': credentials.toJson(),
    'keyId': keyId,
    'teamId': teamId,
    'bundleId': bundleId,
    'useSandbox': useSandbox,
  };
}
