part of rules;

class RecordRules<S extends Collection<R>, R> extends BaseRecordRules<S, R>
    implements Rules<S, R> {
  const RecordRules(super.schema);
}

base class InternalRecordRules<S extends Collection<R>, R>
    extends RecordRules<S, R> {
  const InternalRecordRules(super.schema, {this.canBeOverridden = false});

  final bool canBeOverridden;
}
