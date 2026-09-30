/// `POST /auth/anonymous` -- create an anonymous account in [table].
///
/// [object] carries the app's own columns for the new row, as a sign-up body
/// does. It can never set the address or the verification flag: an anonymous
/// row has neither until it is upgraded.
class AnonymousAuthBody {
  const AnonymousAuthBody({required this.table, this.object});

  factory AnonymousAuthBody.fromJson(Map<String, dynamic> json) {
    return AnonymousAuthBody(
      table: json['table'] as String,
      object: json['object'] as Map<String, dynamic>?,
    );
  }

  final String table;
  final Map<String, dynamic>? object;

  Map<String, dynamic> toJson() => {'table': table, 'object': ?object};
}

/// `POST /auth/anonymous/resume` -- trade the device credential issued at
/// creation for a fresh session. Carries no table: the credential names its
/// account.
class ResumeAnonymousAuthBody {
  const ResumeAnonymousAuthBody({required this.credential});

  factory ResumeAnonymousAuthBody.fromJson(Map<String, dynamic> json) {
    return ResumeAnonymousAuthBody(credential: json['credential'] as String);
  }

  final String credential;

  Map<String, dynamic> toJson() => {'credential': credential};
}

/// `POST /auth/upgrade` -- send a code to [email] for the anonymous session in
/// the `Authorization` header to adopt.
class UpgradeAuthBody {
  const UpgradeAuthBody({required this.email});

  factory UpgradeAuthBody.fromJson(Map<String, dynamic> json) {
    return UpgradeAuthBody(email: json['email'] as String);
  }

  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}

/// `POST /auth/upgrade/confirm` -- prove [code] and give the anonymous account
/// [email], keeping its id. [password], when the table takes one, is set in
/// the same write, after the address is proven.
class ConfirmUpgradeAuthBody {
  const ConfirmUpgradeAuthBody({
    required this.email,
    required this.code,
    this.password,
  });

  factory ConfirmUpgradeAuthBody.fromJson(Map<String, dynamic> json) {
    return ConfirmUpgradeAuthBody(
      email: json['email'] as String,
      code: json['code'] as String,
      password: json['password'] as String?,
    );
  }

  final String email;
  final String code;
  final String? password;

  Map<String, dynamic> toJson() => {
    'email': email,
    'code': code,
    'password': ?password,
  };
}
