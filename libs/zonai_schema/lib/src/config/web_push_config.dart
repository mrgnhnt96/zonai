import 'dart:convert';
import 'dart:typed_data';

/// The VAPID private key Zonai signs its Web Push authorization with.
///
/// Same shape and same reasoning as `ApnsCredentials`: it is an asymmetric
/// **private key**, so baking it into a binary makes rotation a rebuild
/// rather than a file copy.
///
/// Either form holds the key one of two ways, and the courier tells them
/// apart by looking: a PEM block (`-----BEGIN …`, PKCS#8 or SEC1), or the
/// bare base64url P-256 scalar that `web-push generate-vapid-keys` and most
/// VAPID tools print.
sealed class WebPushPrivateKey {
  const WebPushPrivateKey();

  factory WebPushPrivateKey.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      WebPushPrivateKeyFile._type => WebPushPrivateKeyFile(
        json['path'] as String,
      ),
      WebPushPrivateKeyInline._type => WebPushPrivateKeyInline(
        json['key'] as String,
      ),
      final type => throw ArgumentError.value(
        type,
        'type',
        'Invalid Web Push private key type',
      ),
    };
  }

  /// Read from disk at runtime. **Recommended for production.**
  const factory WebPushPrivateKey.file(String path) = WebPushPrivateKeyFile;

  /// The key itself, typically from `String.fromEnvironment` or a pnv secret.
  const factory WebPushPrivateKey.inline(String key) = WebPushPrivateKeyInline;

  Map<String, dynamic> toJson();
}

final class WebPushPrivateKeyFile extends WebPushPrivateKey {
  const WebPushPrivateKeyFile(this.path);

  static const _type = 'file';

  final String path;

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'path': path};

  @override
  bool operator ==(Object other) =>
      other is WebPushPrivateKeyFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class WebPushPrivateKeyInline extends WebPushPrivateKey {
  const WebPushPrivateKeyInline(this.key);

  static const _type = 'inline';

  final String key;

  @override
  Map<String, dynamic> toJson() => {'type': _type, 'key': key};

  @override
  bool operator ==(Object other) =>
      other is WebPushPrivateKeyInline && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Standard Web Push (RFC 8030, 8291, 8292) to browsers and installed PWAs,
/// with no Firebase in the path.
///
/// One VAPID key pair identifies the server to every push service — Chrome's,
/// Firefox's, Safari's — so there is nothing to register anywhere. The
/// browser is handed [publicKey] as `applicationServerKey` when it
/// subscribes, and from then on only a server holding the matching
/// [privateKey] can push to that subscription. Rotating the pair therefore
/// orphans every existing subscription: the push service answers 403 until
/// the app subscribes again with the new public key.
class WebPushConfig {
  const WebPushConfig({
    required this.publicKey,
    required this.privateKey,
    required this.subject,
  });

  factory WebPushConfig.fromJson(Map<String, dynamic> json) => WebPushConfig(
    publicKey: json['publicKey'] as String,
    privateKey: WebPushPrivateKey.fromJson(
      Map<String, dynamic>.from(json['privateKey'] as Map),
    ),
    subject: json['subject'] as String,
  );

  /// The P-256 public key as a base64url uncompressed point (65 bytes,
  /// leading `0x04`) — exactly the string the app passes to
  /// `pushManager.subscribe({applicationServerKey: …})`.
  ///
  /// Sent as the `k=` half of every `Authorization: vapid` header.
  final String publicKey;

  final WebPushPrivateKey privateKey;

  /// Who to contact about this server's traffic: a `mailto:` address or an
  /// `https:` URL. It becomes the VAPID JWT's `sub`, and Apple's push
  /// service refuses a send without one.
  final String subject;

  Map<String, dynamic> toJson() => {
    'publicKey': publicKey,
    'privateKey': privateKey.toJson(),
    'subject': subject,
  };

  /// What is wrong with this config, or empty when it is usable.
  ///
  /// Checked by `AppConfig.validate` so a half-configured Web Push fails at
  /// startup rather than as a 403 from every push service on the first send.
  /// A file-held private key can only be checked for a path here; its
  /// contents are read, and refused, at send time.
  List<String> get errors {
    final errors = <String>[];

    final publicBytes = decodeBase64Url(publicKey);
    if (publicKey.trim().isEmpty) {
      errors.add('push.webPush.publicKey is empty');
    } else if (publicBytes == null ||
        publicBytes.length != 65 ||
        publicBytes.first != 0x04) {
      errors.add(
        'push.webPush.publicKey must be a base64url uncompressed P-256 point '
        '(65 bytes starting 0x04), the same string the app passes as '
        'applicationServerKey',
      );
    }

    switch (privateKey) {
      case WebPushPrivateKeyFile(:final path) when path.trim().isEmpty:
        errors.add('push.webPush.privateKey file path is empty');
      case WebPushPrivateKeyInline(:final key) when key.trim().isEmpty:
        errors.add('push.webPush.privateKey is empty');
      case WebPushPrivateKeyInline(:final key)
          when !key.contains('-----BEGIN') &&
              decodeBase64Url(key)?.length != 32:
        errors.add(
          'push.webPush.privateKey must be a PEM key or a base64url P-256 '
          'private scalar (32 bytes)',
        );
      default:
        break;
    }

    final sub = subject.trim();
    if (sub.isEmpty) {
      errors.add('push.webPush.subject is empty');
    } else if (!(sub.startsWith('mailto:') && sub.length > 7) &&
        !(sub.startsWith('https://') && sub.length > 8)) {
      errors.add(
        'push.webPush.subject must be a mailto: address or an https: URL '
        '(got "$sub")',
      );
    }

    return errors;
  }

  /// Decodes base64url with or without padding (standard base64 too), or
  /// null when it is not base64 at all.
  ///
  /// VAPID tools and browsers print keys unpadded, and `base64Url.decode`
  /// refuses that.
  static Uint8List? decodeBase64Url(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    try {
      return base64Url.decode(base64Url.normalize(trimmed));
    } on FormatException {
      return null;
    }
  }
}
