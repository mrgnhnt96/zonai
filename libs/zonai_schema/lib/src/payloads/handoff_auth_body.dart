import 'package:zonai_schema/src/payloads/parse_body.dart';

/// `POST /auth/handoff` -- ask for a one-time code that buys another client a
/// session of its own for the account in the `Authorization` header.
///
/// [table] is the auth table that account lives in. It keys the rate limit,
/// and a code is refused unless it matches the caller's own table.
/// [codeChallenge] is the PKCE challenge of a secret only that other client
/// holds; [codeChallengeMethod] says how it was made (only `S256`).
class HandoffAuthBody {
  const HandoffAuthBody({
    required this.table,
    required this.codeChallenge,
    this.codeChallengeMethod = 'S256',
  });

  factory HandoffAuthBody.fromJson(Map<String, dynamic> json) =>
      parseBody('HandoffAuthBody', () => HandoffAuthBody._fromJson(json));

  factory HandoffAuthBody._fromJson(Map<String, dynamic> json) {
    return HandoffAuthBody(
      table: json['table'] as String,
      codeChallenge: json['codeChallenge'] as String,
      codeChallengeMethod: json['codeChallengeMethod'] as String? ?? 'S256',
    );
  }

  final String table;
  final String codeChallenge;
  final String codeChallengeMethod;

  Map<String, dynamic> toJson() => {
    'table': table,
    'codeChallenge': codeChallenge,
    'codeChallengeMethod': codeChallengeMethod,
  };
}

/// `POST /auth/handoff/exchange` -- trade the [code] from `POST /auth/handoff`
/// and the PKCE [codeVerifier] behind its challenge for a new session.
///
/// [table] is the auth table the code was made for. It keys the rate limit,
/// and a code made for another table is not found.
class ExchangeHandoffAuthBody {
  const ExchangeHandoffAuthBody({
    required this.table,
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
      table: json['table'] as String,
      code: json['code'] as String,
      codeVerifier: json['codeVerifier'] as String,
    );
  }

  final String table;
  final String code;
  final String codeVerifier;

  Map<String, dynamic> toJson() => {
    'table': table,
    'code': code,
    'codeVerifier': codeVerifier,
  };
}
