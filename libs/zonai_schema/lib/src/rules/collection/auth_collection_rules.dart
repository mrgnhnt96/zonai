part of rules;

base class AuthCollectionRules<T extends AuthCollection<T>>
    extends BaseCollectionRules<T>
    implements Rules<T> {
  const AuthCollectionRules(super.schema);

  @override
  Table<T> get table => Table.getFor(schema);
}
