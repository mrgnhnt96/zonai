part of rules;

base class CollectionRules<S extends Collection<R>, R>
    extends BaseCollectionRules<S, R>
    implements Rules<S, R> {
  const CollectionRules(super.schema);
}
