part of rules;

base class CollectionRules<T extends Collection<T>>
    extends BaseCollectionRules<T>
    implements Rules<T> {
  const CollectionRules(super.schema);

  @override
  Table<T> get table => Table.getFor(schema);
}
