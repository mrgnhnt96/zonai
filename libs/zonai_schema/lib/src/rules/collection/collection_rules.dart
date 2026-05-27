part of rules;

base class CollectionRules<S extends Collection<R>, R>
    extends BaseCollectionRules<S, R>
    implements Rules<S, R> {
  const CollectionRules(super.schema);
}

base class InternalCollectionRules<S extends Collection<R>, R>
    extends CollectionRules<S, R> {
  const InternalCollectionRules(super.schema, {this.canBeOverridden = false});

  final bool canBeOverridden;
}
