part of rules;

base class AuthTableRules<S extends AuthTable<R>, R>
    extends BaseTableRules<S, R>
    implements Rules<S, R> {
  const AuthTableRules(super.schema);

  Future<bool> canAuthenticate(Jwt? jwt, AuthType authType) async {
    return true;
  }
}
