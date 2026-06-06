part of rules;

base class TableRules<S extends Table<R>, R> extends BaseTableRules<S, R>
    implements Rules<S, R> {
  const TableRules(super.schema);
}

base class InternalTableRules<S extends Table<R>, R> extends TableRules<S, R> {
  const InternalTableRules(super.schema, {this.canBeOverridden = false});

  final bool canBeOverridden;
}
