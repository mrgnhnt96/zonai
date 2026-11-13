import 'package:zonai_schema/src/payloads/parse_body.dart';

/// `POST /auth/handoff` -- ask for a one-time code that buys another client a
/// session of its own for the account in the `Authorization` header.
///
/// [codeChallenge] is the PKCE challenge of a secret only that other client
/// holds; [codeChallengeMethod] says how it was made (`S256`).
class HandoffAuthBody {
  const HandoffAuthBody({
    required this.codeChallenge,
    this.codeChallengeMethod = 'S256',
  });

  factory HandoffAuthBody.fromJson(Map<String, dynamic> json) =>
      parseBody('HandoffAuthBody', () => HandoffAuthBody._fromJson(json));

  factory HandoffAuthBody._fromJson(Map<String, dynamic> json) {
    return HandoffAuthBody(
      codeChallenge: json['codeChallenge'] as String,
      codeChallengeMethod: json['codeChallengeMethod'] as String,
    );
  }

  final String codeChallenge;
  final String codeChallengeMethod;

  Map<String, dynamic> toJson() => {
    'codeChallenge': codeChallenge,
    'codeChallengeMethod': codeChallengeMethod,
  };
}

/// `POST /auth/handoff/exchange` -- trade the [code] from `POST /auth/handoff`
/// and the PKCE [codeVerifier] behind its challenge for a new session.
class ExchangeHandoffAuthBody {
  const ExchangeHandoffAuthBody({
    required this.code,
    required this.codeVerifier,
  });

  factory ExchangeHandoffAuthBody.fromJson(Map<String, dynamic> json) =>
      parseBody(
        'ExchangeHandoffAuthBody',
        () => ExchangeHandoffAuthBody._fromJson(json),
      );

  factory ExchangeHandoffAuthBody._fromJson(Map<String, dynamic> json) {
    return ExchangeHandoffAuthBody(
      code: json['code'] as String,
      codeVerifier: json['codeVerifier'] as String,
    );
  }

  final String code;
  final String codeVerifier;

  Map<String, dynamic> toJson() => {'code': code, 'codeVerifier': codeVerifier};
}
