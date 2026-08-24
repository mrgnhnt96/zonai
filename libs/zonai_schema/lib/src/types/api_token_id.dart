import 'package:zonai_schema/src/types/id.dart';

/// Identifies one row in `_api_tokens`.
///
/// Not the credential. The credential is a random string the server keeps
/// only the SHA-256 of; this id is public, appears in logs and in the
/// dashboard, and is what `zonai db token revoke` takes.
class ApiTokenId implements Id {
  ApiTokenId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  factory ApiTokenId.fromJson(String value) => ApiTokenId(value);

  static ApiTokenId generate() => ApiTokenId(Id.generate(_suffix));

  static const _suffix = 'pat';

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
