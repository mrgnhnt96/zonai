part of rules;

base class AuthCollectionRules<S extends AuthCollection<R>, R>
    extends BaseCollectionRules<S, R>
    implements Rules<S, R> {
  const AuthCollectionRules(super.schema);

  Future<bool> canAuthenticate(Jwt? jwt, AuthType authType) async {
    return true;
  }
}
