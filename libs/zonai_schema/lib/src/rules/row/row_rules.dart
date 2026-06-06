part of rules;

class RowRules<S extends Table<R>, R> extends BaseRowRules<S, R>
    implements Rules<S, R> {
  const RowRules(super.schema);
}

base class InternalRowRules<S extends Table<R>, R> extends RowRules<S, R> {
  const InternalRowRules(super.schema, {this.canBeOverridden = false});

  final bool canBeOverridden;
}
